# See the bottom of the file for description, copyright and license information
package Foswiki::Plugins::SubscribePlugin;

use strict;
use Foswiki::Func ();
use Assert;
use Error ':try';
use JSON;

# Simple decimal version, use parse method, no leading "v"
use version; our $VERSION = version->parse("2.0");
our $RELEASE = '2.0';
our $SHORTDESCRIPTION =
'This is a companion plugin to the MailerContrib. It allows you to trivially add a "Subscribe me" link to topics to get subscribed to changes.';
our $NO_PREFS_IN_TOPIC = 1;

our $WEB;
our $TOPIC;

our $tmpls;

sub initPlugin {
    ( $TOPIC, $WEB ) = @_;

    Foswiki::Func::getContext()->{'SubscribePluginAllowed'} = 1;

    # LocalSite.cfg takes precedence. Give admin most control.
    my $activeWebs = $Foswiki::cfg{Plugins}{SubscribePlugin}{ActiveWebs}
      || Foswiki::Func::getPreferencesValue("SUBSCRIBEPLUGIN_ACTIVEWEBS");

    if ($activeWebs) {
        $activeWebs =~ s/\s*\,\s*/\|/go;    # Change comma's to "or"
        $activeWebs =~ s/^\s*//o;           # Drop leading spaces
        $activeWebs =~ s/\s*$//o;           # Drop trailing spaces
             #$activeWebs =~ s/[^$Foswiki::regex{mixedAlphaNum}\|]//go
             #  ;    # Filter any characters not valid in WikiWords
        Foswiki::Func::getContext()->{'SubscribePluginAllowed'} = 0
          unless ( $WEB =~ qr/^($activeWebs)$/ );
    }

    # No subscribe links for pages rendered for static applications (PDF)
    Foswiki::Func::getContext()->{'SubscribePluginAllowed'} = 0
      if ( Foswiki::Func::getContext()->{'static'} );

    Foswiki::Func::registerTagHandler( 'SUBSCRIBE', \&_SUBSCRIBE );
    Foswiki::Func::registerRESTHandler( 'subscribe', \&_rest_subscribe );

    undef $tmpls;
    return 1;
}

# Show a button inviting (un)subscription to this topic
sub _SUBSCRIBE {
    my ( $session, $params, $topic, $web ) = @_;

    return ''
      unless ( Foswiki::Func::getContext()->{'SubscribePluginAllowed'} );

    my $cur_user = Foswiki::Func::getWikiName();
    my $who = $params->{who} || $cur_user;

    # Guest user cannot subscribe
    return '' if ( $who eq $Foswiki::cfg{DefaultUserWikiName} );

    if ( defined $params->{topic} ) {
        ( $web, $topic ) =
          Foswiki::Func::normalizeWebTopicName( $web, $params->{topic} );
    }
    require Foswiki::Contrib::MailerContrib;
    my $unsubscribe =
      ( $params->{unsubscribe}
          || Foswiki::Contrib::MailerContrib::isSubscribedTo( $web, $who,
            $topic ) ) ? 1 : 0;

    my $form = _template_text(
        ( Foswiki::Func::isTrue($unsubscribe) ? 'un' : '' ) . 'form',
        "$web.$topic", $who );

    if ( defined $params->{format} || $params->{formatunsubscribe} ) {

        # Legacy
        my $url = Foswiki::Func::getScriptUrl(
            'SubscribePlugin', 'subscribe', 'rest',
            subscribe_topic      => "$web.$topic",
            subscribe_subscriber => $who,
            subscribe_remove     => $unsubscribe
        );

        $form = $params->{format};
        my $actionName = 'Subscribe';
        if ($unsubscribe) {
            $form = $params->{formatunsubscribe}
              if ( $params->{formatunsubscribe} );
            $actionName = 'Unsubscribe';
        }
        if ($form) {
            $form =~ s/\$action/%MAKETEXT{"$actionName"}%/g;
            $form =~ s/\$url/$url/g;
            $form =~ s/\$wikiname/$who/g;
            $form =~ s/\$topics/$topic/g;
        }
        else {
            $form =
              CGI::a( { href => $url, class => 'subscribe_button' },
                $actionName );
        }
    }

    Foswiki::Plugins::JQueryPlugin::registerPlugin( 'Subscribe',
        'Foswiki::Plugins::SubscribePlugin::JQuery' );
    unless (
        Foswiki::Plugins::JQueryPlugin::createPlugin(
            "Subscribe", $Foswiki::Plugins::SESSION
        )
      )
    {
        die 'Failed to register "subscribe" JQuery plugin';
    }
    return $form;
}

# subscribe_topic (topic is used if subscribe_topic is missing)
# subscribe_subscriber
sub _rest_subscribe {
    my ( $session, $plugin, $verb, $response ) = @_;
    my $query = Foswiki::Func::getCgiQuery();

    ASSERT($query) if DEBUG;

    my $cur_user = Foswiki::Func::getWikiName();
    my $text     = '';
    my $status   = 200;
    my $isSubs   = 0;

    # We have been asked to subscribe
    my $topics = $query->param('subscribe_topic')
      || $query->param('topic');
    unless ($topics) {
        $status = 400;
        $text   = _template_text('no_subscribe_topic');
    }
    else {
        $topics =~ /^(.*)$/;
        $topics = $1;    # Untaint - we will check it later
        my ( $web, $topic ) =
          Foswiki::Func::normalizeWebTopicName( undef, $topics );
        my $who = $query->param('subscribe_subscriber');
        $who ||= $cur_user;
        if ( $who eq $Foswiki::cfg{DefaultUserWikiName} ) {
            $status = 400;
            $text   = _template_text('cannot_subscribe');
        }
        else {
            my $unsubscribe = $query->param('subscribe_remove');
            ( $text, $status ) =
              _subscribe( $web, $topic, $who, $cur_user, $unsubscribe );
            $isSubs =
              Foswiki::Contrib::MailerContrib::isSubscribedTo( $web, $who,
                $topic );
        }
    }

    $response->header(
        -status  => $status,
        -type    => 'text/json',
        -charset => 'UTF-8'
    );
    $response->body(
        JSON::to_json(
            {
                message => $text,
                remove  => ( $isSubs ? 1 : 0 )
            }
        )
    );

    return undef;
}

sub _template_text {
    my $def = shift;
    $tmpls = Foswiki::Func::loadTemplate('subscribe') unless defined $tmpls;
    $def = "sp:$def";

    my $text = Foswiki::Func::expandTemplate($def);

    # Instantiate parameters for maketexts
    my $c = 1;
    foreach my $p (@_) {
        $text =~ s/%PARAM$c%/$p/g;
        $c++;
    }
    return Foswiki::Func::expandCommonVariables($text);
}

# Handle a (un)subscription request
sub _subscribe {
    my ( $web, $topics, $subscriber, $cur_user, $unsubscribe ) = @_;
    my $mess = '';

    return ( _template_text( 'bad_subscriber', $subscriber ), 400 )
      if !(
        (
               $Foswiki::cfg{LoginNameFilterIn}
            && $subscriber =~ m/($Foswiki::cfg{LoginNameFilterIn})/
        )
        || $subscriber =~ m/^([A-Z0-9._%-]+@[A-Z0-9.-]+\.[A-Z]{2,4})$/i
        || $subscriber =~ m/($Foswiki::regex{wikiWordRegex})/o
      )
      || $subscriber eq $Foswiki::cfg{DefaultUserWikiName};
    $subscriber = $1;    # untaint

    if ( Foswiki::Func::isTrue($unsubscribe) ) {
        $unsubscribe = '-';
    }
    else {
        undef $unsubscribe;
    }
    require Foswiki::Contrib::MailerContrib;
    my $status = 200;
    try {
        Foswiki::Contrib::MailerContrib::changeSubscription( $web, $subscriber,
            $topics, $unsubscribe );
        $mess = _template_text( ( $unsubscribe ? 'un' : '' ) . 'subscribe_done',
            $subscriber, $web, $topics );
    }
    catch Error::Simple with {
        $mess = _template_text( 'cannot_change', shift->{-text} );
        $status = 400;
    };
    return ( $mess, $status );
}

1;
__END__

Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2007, 2013 Crawford Currie http://c-dot.co.uk
and Foswiki Contributors. All Rights Reserved. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

For licensing info read LICENSE file in the Foswiki root.

Author: Crawford Currie http://c-dot.co.uk

This plugin supports a subscription button that, when embedded in a topic,
will add the clicker to the WebNotify for that topic. It uses the API
published by the MailerContrib to manage the subscriptions in WebNotify.

WikiGuest cannot be subscribed, only logged-in users.

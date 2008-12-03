# See the bottom of the file for description, copyright and license information
package Foswiki::Plugins::SubscribePlugin;

use strict;
require Foswiki::Func;

use vars qw( $UID $WEB $TOPIC);

our $VERSION = '$Rev: 13787 (18 May 2007) $';
our $RELEASE = '03 Dec 2008';
our $SHORTDESCRIPTION = 'Subscribe to web notification';
our $NO_PREFS_IN_TOPIC = 1;
my $pluginName = 'SubscribePlugin';

our $UID;
our $WEB;
our $TOPIC;

sub initPlugin {
    ( $TOPIC, $WEB ) = @_;

    Foswiki::Func::registerTagHandler( 'SUBSCRIBE', \&_SUBSCRIBE );
    $UID = 1;

    return 1;
}

# Show a button inviting (un)subscription to this topic
sub _SUBSCRIBE {
    my($session, $params, $topic, $web) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    my $form;
    my $suid = $query->param( 'subscribe_uid' );

    my $cur_user = Foswiki::Func::getWikiName();

#SMELL: this means that subscription changes can only happen from a url to a topic
#that contains a %SUBCRIBE% tag, rather than the url params meaning something
#it also leads to incorrect display to the user if subscription data is rendered prior to the processing (like subing while displaying the webNotify topic)
    if ($suid && $suid == $UID) {
	$query->delete( 'subscribe_uid');	#make sure we're not doing this twice..
        # We have been asked to subscribe
        my $topics = $query->param('subscribe_topic');
        $topics =~ /^(.*)$/;
        $topics = $1; # Untaint - we will check it later
        my $who = $query->param('subscribe_subscriber');
        $who ||= $cur_user;
        if ($who eq $Foswiki::cfg{DefaultUserWikiName}) {
            $form = _alert("$who cannot subscribe");
        } else {
            my $unsubscribe = $query->param('subscribe_remove');
            _subscribe($web, $topics, $who, $cur_user, $unsubscribe);
        }
    }

    my $who = $params->{who} || Foswiki::Func::getWikiName();
    if ($who eq $Foswiki::cfg{DefaultUserWikiName}) {
        $form = '';
    } else {
        my $topics = $params->{topic} || $topic;
        my $unsubscribe = 0;
	require Foswiki::Contrib::MailerContrib;
	if (Foswiki::Contrib::MailerContrib::isSubscribedTo($web, $who, $topics)) {
	    $unsubscribe = 'yes';
	}

        my $url;
        if( $Foswiki::Plugins::VERSION < 1.2) {
            $url = Foswiki::Func::getScriptUrl(
                $WEB, $TOPIC, 'view').
                "?subscribe_topic=$topics;subscribe_subscriber=$who;subscribe_remove=$unsubscribe;subscribe_uid=$UID";
        } else {
            $url = Foswiki::Func::getScriptUrl(
                $WEB, $TOPIC, 'view',
                subscribe_topic => $topics,
                subscribe_subscriber => $who,
                subscribe_remove => $unsubscribe,
                subscribe_uid => $UID);
        }

        $form = $params->{format};
        my $actionName = 'Subscribe';
        if ($unsubscribe eq 'yes') {
	        $form = $params->{formatunsubscribe}
              if ($params->{formatunsubscribe});
	        $actionName = 'Unsubscribe';
        }
        if ($form) {
            $form =~ s/\$url/$url/g;
            $form =~ s/\$wikiname/$who/g;
            $form =~ s/\$topics/$topics/g;
            $form =~ s/\$action/%MAKETEXT{"$actionName"}%/g;
        } else {
            $form = CGI::a({href => $url}, $actionName);
        }
    }

    $UID++;
    return $form;
}

sub _alert {
    my( $mess ) = @_;
    return "<span class='foswikiAlert'>$mess</span>";
}

# Handle a (un)subscription request
sub _subscribe {
    my( $web, $topics, $subscriber, $cur_user, $unsubscribe ) = @_;
#print STDERR "_subscribe($web, $topics, $subscriber, $cur_user, $unsubscribe);\n";

    return _alert("bad subscriber '$subscriber'") if
      !(($Foswiki::cfg{LoginNameFilterIn} &&
           $subscriber =~ m/($Foswiki::cfg{LoginNameFilterIn})/) ||
             $subscriber =~ m/^([A-Z0-9._%-]+@[A-Z0-9.-]+\.[A-Z]{2,4})$/i ||
               $subscriber =~ m/($Foswiki::regex{wikiWordRegex})/o) ||
                 $subscriber eq $Foswiki::cfg{DefaultUserWikiName};
    $subscriber = $1; # untaint

    if ($unsubscribe && $unsubscribe =~ /^(on|true|yes)$/i) {
        $unsubscribe = '-';
        #$mess = 'unsubscribed from';
    } else {
	undef $unsubscribe;
    }
    require Foswiki::Contrib::MailerContrib;
    Foswiki::Contrib::MailerContrib::changeSubscription($web, $subscriber, $topics, $unsubscribe);

    #return _alert("$subscriber has been $mess <nop>$web.<nop>$topics");
    return "";
}

1;
__END__

Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2007 Crawford Currie http://c-dot.co.uk
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

package Plugins::GoogleMusic::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;
use base qw(Slim::Web::Settings);

use MIME::Base64;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;

use Plugins::GoogleMusic::GoogleAPI;

my $os = Slim::Utils::OSDetect->getOS();
my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();
my $oauthflow = Plugins::GoogleMusic::GoogleAPI::get_oauth_flow();
my $utils = Plugins::GoogleMusic::GoogleAPI::get_utils();

$prefs->init({
    oauth_authorize_url => '',
    oauth_access_token => '',
    oauth_creds_json => '',
    my_music_album_sort_method => 'artistyearalbum',
    all_access_album_sort_method => 'none',
    max_search_items => 100,
    max_artist_tracks => 25,
    max_related_artists => 10,
});

$prefs->migrate(1, sub { 
    return 1;
});

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_GOOGLEMUSIC');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/GoogleMusic/settings/basic.html');
}

sub handler {
    my ($class, $client, $params) = @_;

    if ($params->{'saveSettings'} && $params->{'oauth_access_token'} &&
        $params->{'device_id'}) {

        $log->error("oauth_access_token: $params->{'oauth_access_token'}");
        $log->error("device_id: $params->{'device_id'}");

        my $credentials = $oauthflow->step2_exchange($params->{'oauth_access_token'});
        my $creds_json = $credentials->to_json();
        $log->error("creds: $creds_json");

	$prefs->set('device_id', $params->{'device_id'});
        $prefs->set('oauth_creds_json', $creds_json);
        $prefs->set('oauth_authorize_url', '');
        $prefs->set('oauth_access_token', '');

        # Logout from Google
        $googleapi->logout();

        # try to login with new oauth creds
        eval {
            $googleapi->oauth_login($utils->bytes_to_string($prefs->get('device_id')), $credentials);
        };
        if ($@) {
            $log->error("Not able to login to Google Play Music: $@");
        }

        if(!$googleapi->is_authenticated()) {
            $params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_FAILED');
            $prefs->set('oauth_creds_json', '');
        } else {
            # $params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_SUCCESS');
            # Load My Music and Playlists
            Plugins::GoogleMusic::Library::refresh();
            Plugins::GoogleMusic::Playlists::refresh();
        }
    }

    # clear device id if it was requested. Also logout in that case
    if ($params->{'saveSettings'} && $params->{'device_id'} eq '') {
        $prefs->set('device_id', '');
        $googleapi->logout();
    }

    # just try to login if all necessary data is present
    # not sure if this is necessary but it probably won't hurt
    if (!$googleapi->is_authenticated()) {
        my $creds_json = $prefs->get('oauth_creds_json');
        my $device_id = $prefs->get('device_id');

        if ($creds_json ne '' && $device_id ne '') {
            # Logout from Google
            $googleapi->logout();

            my $credentials = Plugins::GoogleMusic::GoogleAPI::get_oauth_credentials($creds_json);

            # try to login with new oauth creds
            eval {
                $googleapi->oauth_login($utils->bytes_to_string($device_id), $credentials);
            };
            if ($@) {
                $log->error("Not able to login to Google Play Music: $@");
            }

            if(!$googleapi->is_authenticated()) {
                $params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_FAILED');
                # should we reset the oauth credentials? or is it a hickup?
                # $prefs->set('oauth_creds_json', '');
            } else {
                # $params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_SUCCESS');
                # Load My Music and Playlists
                Plugins::GoogleMusic::Library::refresh();
                Plugins::GoogleMusic::Playlists::refresh();
            }
        } else {
            # $params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_NOT_LOGGED_IN');
            $prefs->set('oauth_authorize_url', $oauthflow->step1_get_authorize_url());
        }
    }

    # set some default logged in status messages if no warning has been set before
    if (!$params->{'warning'}) {
        if(!$googleapi->is_authenticated()) {
            $params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_NOT_LOGGED_IN');
        } else {
            $params->{'warning'} = cstring($client, 'PLUGIN_GOOGLEMUSIC_LOGIN_SUCCESS');
        }
    }

    if ($params->{'saveSettings'}) {
        $prefs->set('all_access_enabled',  $params->{'all_access_enabled'} ? 1 : 0);
        for my $param(qw(my_music_album_sort_method all_access_album_sort_method max_search_items max_artist_tracks max_related_artists device_id)) {
            if ($params->{ $param } ne $prefs->get( $param )) {
                $prefs->set($param, $params->{ $param });
            }
        }
    }

    for my $param(qw(device_id my_music_album_sort_method all_access_enabled all_access_album_sort_method max_search_items max_artist_tracks max_related_artists oauth_authorize_url oauth_access_token)) {
        $params->{'prefs'}->{$param} = $prefs->get($param);
    }

    $params->{'album_sort_methods'} = {
        'none'            => cstring($client, 'NONE'),
        'album'           => cstring($client, 'ALBUM'),
        'artistalbum'     => cstring($client, 'SORT_ARTISTALBUM'),
        'artistyearalbum' => cstring($client, 'SORT_ARTISTYEARALBUM'),
        'yearalbum'       => cstring($client, 'SORT_YEARALBUM'),
        'yearartistalbum' => cstring($client, 'SORT_YEARARTISTALBUM'),
    };

    $params = $class->restartServer($params, 1);

    return $class->SUPER::handler($client, $params);
}

sub getRestartMessage {
    my ($class, $paramRef, $noRestartMsg) = @_;

    # show a link/button to restart SC if this is supported by this platform
    if ($os->canRestartServer()) {

        $paramRef->{'restartUrl'} = $paramRef->{webroot} . $paramRef->{path} . '?restart=1';
        $paramRef->{'restartUrl'} .= '&rand=' . $paramRef->{'rand'} if $paramRef->{'rand'};

        $paramRef->{'warning'} = '<span id="restartWarning">'
            . Slim::Utils::Strings::string('PLUGINS_CHANGED_NEED_RESTART', $paramRef->{'restartUrl'})
            . '</span>';

    } else {

        $paramRef->{'warning'} .= '<span id="popupWarning">'
            . $noRestartMsg
            . '</span>';

    }

    return $paramRef;   
}

sub restartServer {
    my ($class, $paramRef, $needsRestart) = @_;

    if ($needsRestart && $paramRef->{restart} && $os->canRestartServer()) {

        $paramRef->{'warning'} = '<span id="popupWarning">'
            . Slim::Utils::Strings::string('RESTARTING_PLEASE_WAIT')
            . '</span>';

        # delay the restart a few seconds to return the page to the client first
        Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 2, \&_restartServer);
    }

    return $paramRef;
}

sub _restartServer {

    return $os->restartServer();

}

1;

__END__

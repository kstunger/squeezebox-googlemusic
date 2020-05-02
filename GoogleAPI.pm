package Plugins::GoogleMusic::GoogleAPI;

use strict;
use warnings;
use File::Spec::Functions;
use Slim::Utils::Prefs;
use Scalar::Util qw(blessed);

my $prefs = preferences('plugin.googlemusic');

my $inlineDir;
my $googleapi;
my $oauthflow;

sub get {
    if (!blessed($googleapi)) {
        eval {
            $googleapi = Plugins::GoogleMusic::GoogleAPI::Mobileclient->new(
                $Inline::Python::Boolean::false,
                $Inline::Python::Boolean::false,
                $prefs->get('disable_ssl') ? $Inline::Python::Boolean::false : $Inline::Python::Boolean::true);

            $oauthflow = oauth_get_flow($googleapi);
        };
    }
    return $googleapi;
}

sub get_oauth_flow {
    if (!blessed($oauthflow)) {
        get();
    }
    return $oauthflow;
}

sub get_oauth_credentials {
    my $creds_json = shift;
    my $creds = creds_from_json($creds_json);
    return $creds;
}

sub get_device_id {
    my ($username, $password) = @_;

    my $id;
    my $webapi;

    eval {
        $webapi = Plugins::GoogleMusic::GoogleAPI::Webclient->new(
            $Inline::Python::Boolean::false,
            $Inline::Python::Boolean::false,
            $prefs->get('disable_ssl') ? $Inline::Python::Boolean::false : $Inline::Python::Boolean::true);
    };

    if (!blessed($webapi)) {
        return;
    }

    eval {
        $webapi->login($username, $password);
    };

    if (!$webapi->is_authenticated()) {
        return;
    }

    my $devices = $webapi->get_registered_devices();
    for my $device (@$devices) {
        if ($device->{type} eq 'PHONE' and $device->{id} =~ /^0x/) {
            # Omit the '0x' prefix
            $id = substr($device->{id}, 2);
            last;
        } elsif ($device->{type} eq 'IOS' and $device->{id} =~ /^ios:/) {
            # The 'ios:' prefix is required
            $id = $device->{id};
            last;
        }
    }

    $webapi->logout();
    return $id;
}

BEGIN {
    $inlineDir = catdir(Slim::Utils::Prefs::preferences('server')->get('cachedir'), '_Inline');
    mkdir $inlineDir unless -d $inlineDir;
}

use Inline (Config => DIRECTORY => $inlineDir);
use Inline Python => <<'END_OF_PYTHON_CODE';

import gmusicapi
from gmusicapi import Mobileclient, Webclient, CallFailure
from oauth2client.client import OAuth2WebServerFlow
from oauth2client.client import OAuth2Credentials

def oauth_get_flow(mobileclient):
    flow = OAuth2WebServerFlow(**mobileclient.session.oauth._asdict())
    # note: next steps in the oauth flow are:
    # - flow.step1_get_authorize_url()
    # - credentials = flow.step2_exchange(code)
    return flow

def creds_from_json(creds_json):
   return OAuth2Credentials.from_json(creds_json)

def get_version():
    return gmusicapi.__version__

END_OF_PYTHON_CODE


1;

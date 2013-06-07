package Net::MBlox;

# VERSION
our $VERSION = "???";

# ABSTRACT: link to the MBlox api for sending SMS

use HTTP::Request::Common;
use HTTP::Request;
use WWW::Mechanize::GZip;
use JSON::XS;
use MIME::Base64;
use Moo;

has 'consumer_key' => ( is => 'rw', predicate => 1, required => 1);
has 'consumer_secret' => ( is => 'rw', predicate => 1, required => 1);
has 'app_id' => ( is => 'rw', predicate => 1, required => 1);
has 'access_token' => ( is => 'rw', predicate => 1);
has 'api_url' => (is => 'ro', default => 'https://api.mblox.com/v1/apps/');

has 'ua' => (
  is      => 'lazy',
);

sub _build_ua {
  my $self = shift;
  return WWW::Mechanize::GZip->new(
    agent       => "perl-net-mblox $VERSION",
    cookie_jar  => {},
    stack_depth => 1,
    autocheck   => 0,
    keep_alive  => 4,
    timeout     => 60,
  );
}

#on creation do oauth, update when expired.
sub BUILD {
  my $self = shift;
  $self->get_token;
}

sub get_token {
  my $self = shift;
  my $ua = $self->ua;
  $ua->default_header('Content-Type', "application/x-www-form-urlencoded");
  my $auth_basic = $self->consumer_key . ':' . $self->consumer_secret;
  $ua->default_header('Authorization', 'Basic ' . encode_base64($auth_basic));
  my $res = $ua->request(POST 'https://api.mblox.com/oauthv2/accesstoken',
    [grant_type => 'client_credentials']);

  if($res->code == 200) {
    my $json = decode_json($res->content);
    $self->access_token($json->{'access_token'});
  }
}

sub query {
  my $self = shift;

  my @args = @_;

  if (@args == 1) {
    unshift @args, 'GET'; # method by default
  } elsif (@args > 1 and not (grep { $args[0] eq $_ } ('GET', 'POST', 'PUT', 'PATCH', 'HEAD', 'DELETE')) ) {
    unshift @args, 'POST'; # if POST content
  }
  my $request_method = shift @args;
  my $url = shift @args;
  $url = $self->api_url . $self->app_id . '/' . $url unless $url =~ /^https\:/;

  my $data = shift @args;
  my $ua = $self->ua;
  $ua->default_header('Content-Type', "application/json");

  ## always go with login:pass or access_token (for private repos)
  unless ($self->has_access_token) { $self->get_token }

  $ua->default_header('Authorization', "Bearer " . $self->access_token);

  my $req = HTTP::Request->new( $request_method, $url );

  if ($data) {
    my $json = encode_json($data);
    $req->content($json);
  }

  $req->header( 'Content-Length' => length $req->content );
  my $res = $ua->request($req);

  #if denied, re-get token, once, or fail permanently.
  if($res->code == 401) {
    $self->get_token;
    $res = $self->query(@_);
  }
  #warn $res->code;
  #warn $res->as_string;

  $res;
}

=head1 NAME

Net::MBlox - link to the mblox api for sending SMS

=head1 SYNOPSIS

  use WWW::MBlox;

  #new will fetch a token via oauth so you can make requests straight away.
  my $mb = Net::Mblox->new(
    consumer_key => 'key',
    consumer_secret => 'secret',
    app_id => 'xxxxxx',
  );

  $mb->query('sms/outbound/messages',{
    message => "Test SMS",
    destination => 44xxxxxxx,
    originator => 44xxxxxxx,
  });

=cut

1;

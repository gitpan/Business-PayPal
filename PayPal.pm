package Business::PayPal;

use 5.6.1;
use strict;
use warnings;

our $VERSION = '0.01';

use Net::SSLeay 1.14;
use Digest::MD5 qw(md5_hex);
use CGI;


# creates new PayPal object.  Assigns an id if none is provided.
sub new {
    my $invocant = shift;
    my @cert = split /\n\n/, join "", <DATA>;
    my $class = ref($invocant) || $invocant;
    my $self = {
        id => undef,
        address => 'https://www.paypal.com/cgi-bin/webscr',
        certcontent => $cert[0],
        cert => $cert[1],
        @_,
    };
    bless $self, $class;
    $self->{id} = md5_hex(rand()) unless $self->{id};
    return $self;
}

# returns current PayPal id
sub id {
    my $self = shift;
    return $self->{id};
}

#creates a PayPal button
sub button {
    my $self = shift;
    my %buttonparam = (
        cmd                 => '_ext-enter',
        redirect_cmd        => '_xclick',
        button_image        => CGI::image_button(
            -name => 'submit',
            -src => 'http://images.paypal.com/images/x-click-but01.gif',
            -alt => 'Make payments with PayPal',
            ), 
        business            => undef,
        item_name           => undef,
        item_number         => undef,
        image_url           => undef,
        no_shipping         => 1,
        return              => undef,
        cancel_return       => undef,
        no_note             => 1,
        undefined_quantity  => 0,
        notify_url          => undef,
        first_name          => undef,
        last_name           => undef,
        shipping            => undef,
        shipping2           => undef,
        quantity            => undef,
        amount              => undef,
        address1            => undef,
        address2            => undef,
        city                => undef,
        state               => undef,
        zip                 => undef,
        night_phone_a       => undef,
        night_phone_b       => undef,
        night_phone_c       => undef,
        day_phone_a         => undef,
        day_phone_b         => undef,
        day_phone_c         => undef,
        receiver_email      => undef,
        invoice             => undef,
        custom              => $self->{id},
        @_,
    );
    my $key;
    my $content = CGI::start_form( -method => 'POST',
        -action => 'https://www.paypal.com/cgi-bin/webscr',
                                 );
    foreach (keys %buttonparam) {
        next unless defined $buttonparam{$_};
        if ($_ eq 'button_image') {
            $content .= $buttonparam{$_}; 
        }
        else {
            $content .= CGI::hidden( -name => $_,
                                     -default => $buttonparam{$_},
                                   );
        }
    }
    $content .= CGI::endform();
    return $content;
}


# takes a reference to a hash of name value pairs, such as from a CGI query
# object, which should contain all the name value pairs which have been
# posted to the script by PayPal's Instant Payment Notification
# posts that data back to PayPal, checking if the ssl certificate matches,
# and returns success or failure, and the reason.
sub ipnvalidate {
    my $self = shift;
    my $query = shift;
    $$query{cmd} = '_notify-validate';
    my $id = $self->{id};
    my ($succ, $reason) = $self->postpaypal($query); 
    return (wantarray ? ($id, $reason) : $id)
        if $succ;
    return (wantarray ? (undef, $reason) : undef);
}

# this method should not normally be used unless you need to test, or if
# you are overriding the behaviour of ipnvalidate.  It takes a reference
# to a hash containing the query, posts to PayPal with the data, and returns
# success or failure, as well as PayPal's respons.
sub postpaypal {
    my $self = shift;
    my $address = $self->{address};
    my $cert = $self->{cert};
    my $certcontent = $self->{certcontent};
    my $query = shift; # reference to hash containing name value pairs
    my ($site, $port, $path);

    #following code splits an url into site, port and path components
    my @address = split /:\/\//, $address, 2;
    @address = split /(?=\/)/, $address[1], 2;
    if ($address[0] =~ /:/) {
        ($site, $port) = split /:/, $address[0];
    }
    else {
        ($site, $port) = ($address[0], '443');
    }
    $path = $address[1];
    my ($page, 
        $response, 
        $headers, 
        $ppcert, 
        ) = Net::SSLeay::post_https3($site, 
                                         $port, 
                                         $path, 
                                         '', 
                                         Net::SSLeay::make_form(%$query));


    my $ppx509 = Net::SSLeay::PEM_get_string_X509($ppcert);
    my $ppcertcontent =
    'Subject Name: '
        . Net::SSLeay::X509_NAME_oneline(
               Net::SSLeay::X509_get_subject_name($ppcert))
            . "\nIssuer  Name: "
                . Net::SSLeay::X509_NAME_oneline(
                       Net::SSLeay::X509_get_issuer_name($ppcert))
                    . "\n";

    chomp $cert;
    chomp $ppx509;
    chomp $ppcertcontent;
    chomp $certcontent;
    return (wantarray ? (undef, "PayPal cert failed to match") : undef)  
        unless $cert eq $ppx509;
    return (wantarray ? (undef, "PayPal cert contents failed to match") : undef)        unless $ppcertcontent eq "$certcontent";
    return (wantarray ? (undef, 'PayPal says transaction INVALID') : undef)
        if $page eq 'INVALID';
    return (wantarray ? (1, 'PayPal says transaction VERIFIED') : 1)
        if $page eq 'VERIFIED';
    warn "Bad stuff happened\n$page";
    return (wantarray ? (undef, "Bad stuff happened") :undef);
}

 

1;

=head1 NAME

Business::PayPal - Perl extension for automating PayPal transactions

=head1 ABSTRACT

Business::PayPal makes the automation of PayPal transactions as simple
as doing credit card transactions through a regular processor.  It includes
methods for creating PayPal buttons and for validating the Instant Payment
Notification that is sent when PayPal processes a payment.

=head1 SYNOPSIS

  To generate a PayPal button for use on your site
  Include something like the following in your CGI

  use Business::PayPal;
  my $paypal = Business::PayPal->new;
  my $button = $paypal->button(
      business => 'dr@dursec.com',
      item_name => 'CanSecWest Registration Example',
      return => 'http://www.cansecwest.com/return.cgi',
      cancel_return => 'http://www.cansecwest.com/cancel.cgi',
      amount => '1600.00',
      quantity => 1,
      notify_url => http://www.cansecwest.com/ipn.cgi
  );
  my $id = $paypal->id;

  #store $id somewhere so we can get it back again later
  #store current context with $id
  #Apache::Session works good for this
  #print button to the browser
  #note, button is a CGI form, enclosed in <form></form> tags



  To validate the Instant Payment Notification from PayPal for the 
  button used above include something like the following in your 
  'notify_url' CGI.

  use CGI;
  my $query = new CGI;
  my %query = $query->Vars;
  my $id = $query{custom};
  my $paypal = Business::PayPal->new($id);
  my ($txnstatus, $reason) = $paypal->ipnvalidate(\%query);
  die "PayPal failed: $reason" unless $txnstatus;
  my $money = $query{payment_gross};
  my $paystatus = $query{payment_status};
  
  #check if paystatus eq 'Completed'
  #check if $money is the ammount you expected
  #save payment status information to store as $id


  To tell the user if their payment succeeded or not, use something like
  the following in the CGI pointed to by the 'return' parameter in your
  PayPal button.

  use CGI;
  my $query = new CGI;
  my $id = $query{custom};

  #get payment status from store for $id
  #return payment status to customer


=head1 DESCRIPTION

=head2 new()

  Creates a new Business::PayPal object, it can take the 
  following parameters:

=over 2

=item id  

  - The Business::PayPal object id, if not specified a new 
    id will be created using md5_hex(rand())

=item address

  - The address of PayPal's payment server, currently:
    https://www.paypal.com/cgi-bin/webscr

=item cert

  - The x509 certificate for I<address>, see source for default

=item certcontent 

  - The contents of the x509 certificate I<cert>, see source for 
    default

=back

=head2 id()

  Returns the id for the Business::PayPal object. 

=head2 button()

  Returns the HTML for a PayPal button.  It takes a large number of
  parameters, which control the look and function of the button, some
  of which are required and some of which have defaults.  They are
  as follows:

=over 2

=item cmd

  required, defaults to '_ext-enter'
  This allows the user information to be pre-filled in.
  You should never need to specify this, as the default should 
  work fine.

=item redirect_cmd

  required, defaults to '_xclick'
  This allows the user information to be pre-filled in.
  You should never need to specify this, as the default should 
  work fine.

=item button_image

  required, defaults to:

    CGI::image_button(-name ='submit',
                      -src => 'http://images.paypal.com/x-click-but01.gif'
                      -alt => 'Make payments with PayPal',
                     )

  You may wish to change this if the button is on an https page 
  so as to avoid the browser warnings about insecure content on a 
  secure page.

=item business

  required, no default
  This is the name of your PayPal account.

=item item_name

  This is the name of the item you are selling.

=item item_number

  This is a numerical id of the item you are selling.

=item image_url

  A URL pointing to a 150 x 50 image which will be displayed 
  instead of the name of your PayPal account.

=item no_shipping

  defaults to 1
  If set to 1, does not ask customer for shipping info, if 
  set to 0 the customer will be prompted for shipping information.

=item return

  This is the URL to which the customer will return to after 
  they have finished paying.

=item cancel_return

  This is the URL to which the customer will be sent if they cancel
  before paying.

=item no_note

  defaults to 1
  If set to 1, does not ask customer for a note with the payment, 
  if set to 0, the customer will be asked to include a note.

=item undefined_quantity

  defaults to 0
  If set to 0 the quantity defaults to 1, if set to 1 the user 
  can edit the quantity.

=item notify_url

  The URL to which PayPal Instant Payment Notification is sent.

=item first_name

  First name of customer, used to pre-fill PayPal forms.

=item last_name

  Last name of customer, used to pre-fill PayPal forms.

=item shipping

  I don't know, something to do with shipping, please tell me if
  you find out.

=item shipping2

  I don't know, something to do with shipping, please tell me if you
  find out.

=item quantity

  defaults to 1
  Number of items being sold.

=item amount

  Price of the item being sold.

=item address1

  Address of customer, used to pre-fill PayPal forms.

=item address2

  Address of customer, used to pre-fill PayPal forms.

=item city

  City of customer, used to pre-fill PayPal forms.

=item state

  State of customer, used to pre-fill PayPal forms.

=item zip

  Zip of customer, used to pre-fill PayPal forms.

=item night_phone_a

  Phone

=item night_phone_b

  Phone

=item night_phone_c

  Phone

=item day_phone_a

  Phone

=item day_phone_b

  Phone

=item day_phone_c

  Phone

=item receiver_email

  Email address of customer - I think

=item invoice

  Invoice number - I think

=item custom

  defaults to the Business::PayPal id
  Used by Business::PayPal to track which button is associated 
  with which Instant Payment Notification.

=back

=head2 ipnvalidate()

  Takes a reference to a hash of name value pairs, such as from a 
  CGI query object, which should contain all the name value pairs 
  which have been posted to the script by PayPal's Instant Payment 
  Notification posts that data back to PayPal, checking if the ssl 
  certificate matches, and returns success or failure, and the 
  reason.

=head2 postpaypal()

  This method should not normally be used unless you need to test, 
  or if you are overriding the behaviour of ipnvalidate.  It takes a 
  reference to a hash containing the query, posts to PayPal with 
  the data, and returns success or failure, as well as PayPal's 
  response.

=head1 AUTHOR

mock, E<lt>mock@obscurity.orgE<gt>

=head1 SEE ALSO

L<CGI>, L<perl>, L<Apache::Session>.

https://www.cansecwest.com/register.cgi is currently using this module
to do conference registrations.  If you wish to see it working, just
fill out the forms until you get to the PayPal button, click on the button,
and then cancel before paying (or pay, and come to CanSecWest :-) ).

=head1 LICENSE

Copyright (c) 2002, mock E<lt>mock@obscurity.orgE<gt>.  All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__DATA__
Subject Name: /C=US/ST=California/L=Palo Alto/O=Paypal, Inc./OU=Information Systems/CN=www.paypal.com
Issuer  Name: /O=VeriSign Trust Network/OU=VeriSign, Inc./OU=VeriSign International Server CA - Class 3/OU=www.verisign.com/CPS Incorp.by Ref. LIABILITY LTD.(c)97 VeriSign

-----BEGIN CERTIFICATE-----
MIIEXTCCA8agAwIBAgIQJxYkWks944byj39QYE8jujANBgkqhkiG9w0BAQQFADCB
ujEfMB0GA1UEChMWVmVyaVNpZ24gVHJ1c3QgTmV0d29yazEXMBUGA1UECxMOVmVy
aVNpZ24sIEluYy4xMzAxBgNVBAsTKlZlcmlTaWduIEludGVybmF0aW9uYWwgU2Vy
dmVyIENBIC0gQ2xhc3MgMzFJMEcGA1UECxNAd3d3LnZlcmlzaWduLmNvbS9DUFMg
SW5jb3JwLmJ5IFJlZi4gTElBQklMSVRZIExURC4oYyk5NyBWZXJpU2lnbjAeFw0w
MjAzMTMwMDAwMDBaFw0wNDAzMTIyMzU5NTlaMIGEMQswCQYDVQQGEwJVUzETMBEG
A1UECBMKQ2FsaWZvcm5pYTESMBAGA1UEBxQJUGFsbyBBbHRvMRUwEwYDVQQKFAxQ
YXlwYWwsIEluYy4xHDAaBgNVBAsUE0luZm9ybWF0aW9uIFN5c3RlbXMxFzAVBgNV
BAMUDnd3dy5wYXlwYWwuY29tMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCm
xcPGW6myyBznfmpSX8SuSIOKKXIz3ROHi/TVYeE5tm316LtLsu10rqOHWKggl36H
eW8VN+daS3qblzi4ajqMuhDZOvGZSvSBzZKG7Y00wy5Z9LlH07+9fLp6L1SxCFo2
HZVTZXLIW3dbbXXf0j5V5tjeH94nK1y1nRHrCbAAKQIDAQABo4IBljCCAZIwCQYD
VR0TBAIwADCBrAYDVR0gBIGkMIGhMIGeBgtghkgBhvhFAQcBATCBjjAoBggrBgEF
BQcCARYcaHR0cHM6Ly93d3cudmVyaXNpZ24uY29tL0NQUzBiBggrBgEFBQcCAjBW
MBUWDlZlcmlTaWduLCBJbmMuMAMCAQEaPVZlcmlTaWduJ3MgQ1BTIGluY29ycC4g
YnkgcmVmZXJlbmNlIGxpYWIuIGx0ZC4gKGMpOTcgVmVyaVNpZ24wEQYJYIZIAYb4
QgEBBAQDAgZAMCgGA1UdJQQhMB8GCWCGSAGG+EIEAQYIKwYBBQUHAwEGCCsGAQUF
BwMCMDQGCCsGAQUFBwEBBCgwJjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AudmVy
aXNpZ24uY29tMEYGA1UdHwQ/MD0wO6A5oDeGNWh0dHA6Ly9jcmwudmVyaXNpZ24u
Y29tL0NsYXNzM0ludGVybmF0aW9uYWxTZXJ2ZXIuY3JsMBsGCmCGSAGG+EUBBg8E
DRYLMDgtMDI5LTM5MDAwDQYJKoZIhvcNAQEEBQADgYEAum8UDgBwY7f4+OV3dFzc
dLFO39dcrw+mx+tfI4KuqdEwDRirk57nxVuuJa2yjN+T5hUfnxrYqzLsfnYWwaia
oBiz/YiehkC+zhlae5ekxYy/EiiUzyWRFtpjY1wbBZk4j1RcOPcL7A6MihFcduWp
sM+AeBP+TLqtVikM9XWsg/U=
-----END CERTIFICATE-----


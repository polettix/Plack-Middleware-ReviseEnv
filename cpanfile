requires 'perl',  '5.008001';
requires 'Plack', '1.0039';
requires 'parent';

on test => sub {
   requires 'Test::More', '0.88';
   requires 'HTTP::Message', '0';
   requires 'Path::Tiny', '0.096';
};

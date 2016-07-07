package TestPackage;
sub factory { return sub { 'works!' } }
sub mangler { return 'works!' }
1;

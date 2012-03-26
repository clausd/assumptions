#!perl -I.
use ATest;

sub index {
    
}

sub smartsave {
    my $app = shift;
    #~ print ref($app->db->testtable);
    $record = $app->db->testtable->addmod({string_value=>'existing'});
    $record->set(string_value=>'existing', strange_value=>'has value');
    $record->save('string_value');
}


my $app = new ATest;
$app->setup;
$app->dispatch;


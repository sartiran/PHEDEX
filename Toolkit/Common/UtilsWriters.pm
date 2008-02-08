package UtilsWriters; use strict; use warnings; use base 'Exporter';
our @EXPORT = qw(outputCatalog genXMLPreamble genXMLTrailer
		 genXMLCatalogue genXMLOneFile);
use UtilsCommand;

sub genXMLPreamble
{
    return ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\" ?>\n"
	    . "<!DOCTYPE POOLFILECATALOG SYSTEM \"InMemory\"><POOLFILECATALOG>\n"
	    . '  <META name="Content" type="string"/>' . "\n"
	    . '  <META name="DBoid" type="string"/>' . "\n"
	    . '  <META name="DataType" type="string"/>' . "\n"
	    . '  <META name="FileCategory" type="string"/>' . "\n"
            . '  <META name="Flags" type="string"/>' . "\n"
	    . '  <META name="dataset" type="string"/>' . "\n"
       	    . '  <META name="jobid" type="string"/>' . "\n"
	    . '  <META name="owner" type="string"/>' . "\n"
	    . '  <META name="runid" type="string"/>' . "\n");
}

sub genXMLTrailer
{
    return "</POOLFILECATALOG>\n";
}

sub genXMLOneFile
{
    my ($file) = @_;
    my $content = "";
    $content .= "  <File ID=\"$file->{GUID}\">\n";
    $content .= "    <physical>\n";
    foreach my $pfn (@{$file->{PFN}})
    {
	$content .= "      <pfn filetype=\"$pfn->{TYPE}\" name=\"$pfn->{PFN}\"/>\n";
    }
    $content .= "    </physical>\n";

    $content .= "    <logical>\n";
    foreach my $lfn (@{$file->{LFN}})
    {
	$content .= "      <lfn name=\"$lfn\"/>\n";
    }
    $content .= "    </logical>\n";

    foreach my $m (sort keys %{$file->{META}}) {
	my $value = $file->{META}{$m};
	$value = '' if ! defined $value;
	$content .= "   <metadata att_name=\"$m\" att_value=\"$value\"/>\n";
    }

    $content .= "  </File>\n";
    return $content;
}

sub genXMLCatalogue
{
    my @files = @_;

    my $content = &genXMLPreamble();
    foreach my $file (@files)
    {
	$content .= &genXMLOneFile ($file);
    }

    $content .= &genXMLTrailer();
    return $content;
}

sub outputCatalog
{
    my ($file, $content) = @_;
    return &output ($file, &genXMLPreamble() . $content . &genXMLTrailer());
}

print STDERR "WARNING:  use of Common/UtilsWriters.pm is depreciated.  Update your code to use the PHEDEX perl library!\n";
1;

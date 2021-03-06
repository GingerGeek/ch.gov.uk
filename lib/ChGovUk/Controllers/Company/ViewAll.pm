package ChGovUk::Controllers::Company::ViewAll;

use Mojo::Base 'Mojolicious::Controller';
use CH::Perl;

  my @snapshot_company_types = (
    "assurance-company",
    "industrial-and-provident-society",
    "royal-charter",
    "investment-company-with-variable-capital",
    "charitable-incorporated-organisation",
    "scottish-charitable-incorporated-organisation",
    "uk-establishment",
    "registered-society-non-jurisdictional",
    "protected-cell-company",
    "eeig",
    "protected-cell-company",
    "further-education-or-sixth-form-college-corporation",
    "icvc-securities",
    "icvc-warrant",
    "icvc-umbrella");

  my @certificate_orders_company_types = (
    "limited-partnership",
    "llp",
    "ltd",
    "plc",
    "old-public-company",
    "private-limited-guarant-nsc",
    "private-limited-guarant-nsc-limited-exemption",
    "private-limited-shares-section-30-exemption",
    "private-unlimited",
    "private-unlimited-nsc");

  my @dissolved_certificate_orders_company_types = (
      "llp",
      "ltd",
      "plc",
      "old-public-company",
      "private-limited-guarant-nsc",
      "private-limited-guarant-nsc-limited-exemption",
      "private-limited-shares-section-30-exemption",
      "private-unlimited",
      "private-unlimited-nsc");

#-------------------------------------------------------------------------------

# View All Tab
sub view {
  my ($self) = @_;

  my $company = $self->stash->{company};
  my $company_type = $company->{type};
  my $company_status = $company->{company_status};
  my $links = $company->{links};
  my $filing_history = $links->{filing_history};
  my $show_snapshot = 1;
  my $show_certificate = 0;
  my $show_certified_document = 1;
  my $show_dissolved_certificate = 0;

  for (my $i=0; $i < @snapshot_company_types; $i++) {
    if ($company_type eq $snapshot_company_types[$i]) {
      $show_snapshot = 0;
    }
  }

  if ($company_status eq 'active') {
    for (my $j=0; $j < @certificate_orders_company_types; $j++) {
      if ($company_type eq $certificate_orders_company_types[$j]) {
        $show_certificate = 1;
      }
    }
  }

  if ($filing_history eq "" || ($filing_history ne "" && $company_type eq "uk-establishment")) {
      $show_certified_document = 0;
  }

  if ($company_status eq 'dissolved') {
    for (my $j=0; $j < @dissolved_certificate_orders_company_types; $j++) {
      if ($company_type eq $dissolved_certificate_orders_company_types[$j]) {
        $show_dissolved_certificate = 1;
      }
    }
  }

  $self->stash(show_snapshot => $show_snapshot);
  $self->stash(show_certificate => $show_certificate);
  $self->stash(show_certified_document => $show_certified_document);
  $self->stash(show_dissolved_certificate => $show_dissolved_certificate);

  if ($show_snapshot || $show_certificate || $show_certified_document || $show_dissolved_certificate) {
    return $self->render(template => 'company/view_all/view');
  } else {
    return $self->render(template => 'not_found.production');
  }
}

#-------------------------------------------------------------------------------

1;
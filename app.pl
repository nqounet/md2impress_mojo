#!/usr/bin/env perl
use utf8;
use Mojolicious::Lite;
use Mojo::ByteStream qw(b);

use Path::Class qw(file dir);
use Text::Markdown qw( markdown );
use List::Util qw(min max);

app->secret(b(file(__FILE__)->absolute)->sha1_sum);

helper markdowns_dir => sub {
  my ($self) = @_;
  my $home = $self->app->home->detect;
  return dir($home, 'markdowns');
};

helper overview => sub {1};# or 0

helper parse_markdown => sub {
  my ($self, $md) = @_;
  my %opts = (
    width      => 1024,
    height     => 768,
    max_column => 5,
  );

  my ($content, $min_x, $min_y, $max_x, $max_y);
  my @sections = $md =~ /(^#+.*?)(?:(?=^#+)|\z)/msg;
  $opts{max_column}  = int( @sections ** (1/2) + 1 );
  my $bored          = 1;
  my $x              = 0;
  my $y              = 0;
  my $current_column = 0;
  $min_x = $max_x    = 0;
  $min_y = $max_y    = 0;
  for my $section (@sections) {
    my %attrs;
    $attrs{class} = 'step';    # default
    while ($section =~ /^<!\-{2,}\s*([^\s]+)\s*\-{2,}>/gm) {
      my $attr = $1;
      if ($attr =~ /(.+)="?([^"]+)?"?/) {
        $attrs{$1} = $attrs{$1} ? [$attrs{$1}, $2] : $2;
      }
    }
    if (!defined $attrs{id} && $x == 0 && $y == 0) {
      $attrs{id} = 'title';    # for first presentation
    }
    unless (defined $attrs{'data-x'}) {
      $attrs{'data-x'} = $x;
      $x += $opts{width};
    }
    unless (defined $attrs{'data-y'}) {
      $attrs{'data-y'} = $y;
      $current_column++;
      if ($current_column >= $opts{max_column}) {
        $x = 0;
        $y += $opts{height};
        $current_column = 0;
      }
    }
    my $attrs = join ' ', map {
      if (ref $attrs{$_} eq 'ARRAY')
      {
        sprintf '%s="%s"', $_, join ' ', @{$attrs{$_}};
      }
      else {
        sprintf '%s="%s"', $_, $attrs{$_};
      }
    } keys %attrs;
    my $markdown = markdown($section);
    $markdown =~ s/<pre>/<pre class="lang-perl prettyprint linenums">/msg;
    $content .= sprintf '<div %s>%s</div>', $attrs, $markdown;
    $bored = undef;
    $min_x = min($min_x, $x);
    $min_y = min($min_y, $y);
    $max_x = max($max_x, $x);
    $max_y = max($max_y, $y);
  }
  return {
    content => $content,
    cx => ($min_x + $max_x) / 2,
    cy => ($min_y + $max_y) / 2,
    opts => $opts{max_column},
  };
};

get '/' => sub {
  my ($self) = @_;
  my $dir = $self->markdowns_dir;# Path::Class
  my @markdown_files;
  for my $child ($dir->children) {
    next if $child->is_dir;
    next unless $child->basename =~ /\.md\z/;
    push @markdown_files, $child;
  }

  $self->render(
    template => 'index',
    markdown_files => \@markdown_files,
  );
};

get '/single/*filename' => sub {
  my ($self) = @_;

  my $filename = $self->param('filename');
  unless ($filename =~ /\A\w+\.md\z/) {
    $self->render_not_found;
    return;
  }
  my $file = file($self->markdowns_dir, $filename);
  unless (-r $file) {
    $self->render_not_found;
    return;
  }
  my $slide = $self->parse_markdown(b($file->slurp)->decode);
  $self->render(
    template => 'single',
    presentation  => $slide->{content},
    cx => $slide->{cx},
    cy => $slide->{cy},
    scale => $slide->{opts},
  );
};


app->start;

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html>
<head>
  <meta charset="<%= app->renderer->encoding %>">
  <title><%= title %></title>
</head>
<body>
<ul>
% for my $file (sort @{$markdown_files}) {
  % my $basename = $file->basename;
  <li><%= link_to $basename => qq{/single/$basename} %></li>
% }
</ul>
</body>
</html>


@@ single.html.ep
<!DOCTYPE html>
<html>
<head>
  <meta charset="<%= app->renderer->encoding %>">
  <meta name="viewport" content="width=1024" />
  <meta name="apple-mobile-web-app-capable" content="yes" />
  <title><%= title %></title>
  <link href="http://fonts.googleapis.com/css?family=Open+Sans:regular,semibold,italic,italicsemibold|PT+Sans:400,700,400italic,700italic|PT+Serif:400,700,400italic,700italic" rel="stylesheet" />
  <%= stylesheet '/impress/css/impress-demo.css' %>
  <%= stylesheet '/gcp/prettify.css' %>
  <%= stylesheet '/css/app.css' %>
</head>
<body class="impress-not-supported">

<div class="fallback-message">
    <p>Your browser <b>doesn't support the features required</b> by impress.js, so you are presented with a simplified version of this presentation.</p>
    <p>For the best experience please use the latest <b>Chrome</b>, <b>Safari</b> or <b>Firefox</b> browser.</p>
</div>

<div id="impress">
  <%== $presentation %>
  % if (overview) {
    <div id="overview" class="step" data-x="<%= $cx %>" data-y="<%= $cy %>" data-scale="<%= $scale %>"></div>
  % }
</div>

<div class="hint">
  <p>Use a spacebar or arrow keys to navigate</p>
</div>
<script>
if ("ontouchstart" in document.documentElement) {
  document.querySelector(".hint").innerHTML = "<p>Tap on the left or right to navigate</p>";
}
</script>
<%= javascript '/impress/js/impress.js' %>
<%= javascript '/gcp/prettify.js' %>
<%= javascript '/js/app.js' %>
</body>
</html>

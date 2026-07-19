# frozen_string_literal: true

require "fileutils"

SITE_ROOT = "https://kanutocd.github.io/mammoth/"
SOCIAL_PREVIEW_URL = "#{SITE_ROOT}mammoth-social-preview-1280x640.png".freeze
DOCS_LOGO_FILENAME = "mammoth-primary-horizontal-light.png"
README_LOGO_REFERENCES = [
  "https://raw.githubusercontent.com/kanutocd/mammoth/main/docs/branding/logo/" \
  "exports/png/mammoth-primary-horizontal-light.png",
  "https://raw.githubusercontent.com/kanutocd/mammoth/main/docs/branding/logo/" \
  "exports/png/mammoth-primary-horizontal-reversed-transparent.png"
].freeze

def insert_before_head!(html, html_file, content)
  return if html.sub!(%r{</head>}i, "  #{content}\n</head>")

  abort("Unable to find </head> in #{html_file}")
end

def install_favicon(html, html_file, favicon_target)
  return if html.include?('data-mammoth-branding="favicon"')

  relative_favicon = favicon_target.relative_path_from(html_file.dirname)
  favicon_link = <<~HTML.chomp
    <link rel="icon" href="#{relative_favicon}" sizes="any" data-mammoth-branding="favicon">
  HTML
  insert_before_head!(html, html_file, favicon_link)
end

def page_url(output_root, html_file)
  relative_page = html_file.relative_path_from(output_root).to_s
  return SITE_ROOT if relative_page == "index.html"

  "#{SITE_ROOT}#{relative_page}"
end

def install_social_metadata(html, html_file, output_root)
  return if html.include?('data-mammoth-branding="social"')

  canonical_url = page_url(output_root, html_file)
  metadata = <<~HTML.chomp
    <link rel="canonical" href="#{canonical_url}" data-mammoth-branding="social">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="Mammoth">
    <meta property="og:title" content="Mammoth — PostgreSQL CDC Data Plane">
    <meta property="og:description" content="Reliable PostgreSQL change-data-capture delivery with durable checkpoints, retries, dead letters, and webhook fan-out.">
    <meta property="og:url" content="#{canonical_url}">
    <meta property="og:image" content="#{SOCIAL_PREVIEW_URL}">
    <meta property="og:image:type" content="image/png">
    <meta property="og:image:width" content="1280">
    <meta property="og:image:height" content="640">
    <meta property="og:image:alt" content="Mammoth — PostgreSQL CDC Data Plane. Carry Every Transaction.">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="Mammoth — PostgreSQL CDC Data Plane">
    <meta name="twitter:description" content="Reliable PostgreSQL CDC delivery with durable operational state and webhook fan-out.">
    <meta name="twitter:image" content="#{SOCIAL_PREVIEW_URL}">
  HTML
  insert_before_head!(html, html_file, metadata)
end

def install_docs_logo(html, html_file, logo_target)
  relative_logo = logo_target.relative_path_from(html_file.dirname).to_s
  README_LOGO_REFERENCES.each do |reference|
    html.gsub!(reference, relative_logo)
  end
end

output_root = Pathname(ARGV.fetch(0)).expand_path
favicon_source = Pathname(__dir__).join(
  "../docs/branding/logo/exports/favicon/favicon.ico"
).expand_path
social_preview_source = Pathname(__dir__).join(
  "../docs/branding/logo/social/mammoth-social-preview-1280x640.png"
).expand_path
docs_logo_source = Pathname(__dir__).join(
  "../docs/branding/logo/exports/png/#{DOCS_LOGO_FILENAME}"
).expand_path

abort("Documentation output does not exist: #{output_root}") unless output_root.directory?
abort("Favicon source does not exist: #{favicon_source}") unless favicon_source.file?
abort("Social preview source does not exist: #{social_preview_source}") unless social_preview_source.file?
abort("Documentation logo source does not exist: #{docs_logo_source}") unless docs_logo_source.file?

favicon_target = output_root.join("favicon.ico")
social_preview_target = output_root.join("mammoth-social-preview-1280x640.png")
docs_logo_target = output_root.join(DOCS_LOGO_FILENAME)
FileUtils.cp(favicon_source, favicon_target)
FileUtils.cp(social_preview_source, social_preview_target)
FileUtils.cp(docs_logo_source, docs_logo_target)

Dir.glob(output_root.join("**/*.html")).each do |html_path|
  html_file = Pathname(html_path)
  html = html_file.read(encoding: Encoding::UTF_8)
  install_favicon(html, html_file, favicon_target)
  install_social_metadata(html, html_file, output_root)
  install_docs_logo(html, html_file, docs_logo_target)
  html_file.write(html)
end

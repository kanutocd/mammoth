# frozen_string_literal: true

require "fileutils"

output_root = Pathname(ARGV.fetch(0)).expand_path
favicon_source = Pathname(__dir__).join(
  "../docs/branding/logo/frozen-no-nonsense/exports/favicon/favicon.ico"
).expand_path

abort("Documentation output does not exist: #{output_root}") unless output_root.directory?
abort("Favicon source does not exist: #{favicon_source}") unless favicon_source.file?

favicon_target = output_root.join("favicon.ico")
FileUtils.cp(favicon_source, favicon_target)

Dir.glob(output_root.join("**/*.html")).each do |html_path|
  html_file = Pathname(html_path)
  html = html_file.binread
  next if html.include?('data-mammoth-branding="favicon"')

  relative_favicon = favicon_target.relative_path_from(html_file.dirname)
  favicon_link = <<~HTML.chomp
    <link rel="icon" href="#{relative_favicon}" sizes="any" data-mammoth-branding="favicon">
  HTML

  abort("Unable to find </head> in #{html_file}") unless html.sub!(%r{</head>}i, "  #{favicon_link}\n</head>")

  html_file.binwrite(html)
end

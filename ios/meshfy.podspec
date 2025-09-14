Pod::Spec.new do |s|
  s.name             = 'meshfy'
  s.version          = '0.7.5'
  s.summary          = 'Meshfy Flutter plugin (stub native layer).'
  s.description      = 'Stub native plugin that acknowledges emitFrame for integration.'
  s.homepage         = 'https://github.com/GhostMadi/meshfy_package_v7'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'GhostMadi' => 'none@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.static_framework = true
  s.swift_version = '5.0'
end

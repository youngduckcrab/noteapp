#
# pencil_bridge (INFRA, docs/plans/m5-7/01-infra.md 3.3 and 6.12). CocoaPods
# spec for apps that do not use Swift Package Manager; the sources are the
# SwiftPM target's (ios/pencil_bridge/Sources/pencil_bridge/).
#
Pod::Spec.new do |s|
  s.name             = 'pencil_bridge'
  s.version          = '0.1.0'
  s.summary          = 'Apple Pencil double tap, squeeze, hover and barrel roll events.'
  s.description      = <<-DESC
Apple Pencil double tap, squeeze, hover and barrel roll events (iOS only).
                       DESC
  s.homepage         = 'https://example.invalid/noteapp'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'noteapp' => 'noteapp@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files = 'pencil_bridge/Sources/pencil_bridge/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end

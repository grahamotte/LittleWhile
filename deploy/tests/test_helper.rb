require "bundler/setup"
require "minitest/autorun"
require "minitest/parallel_fork"
require "mocha/minitest"
require "webmock/minitest"
require "test_safety"
require "tmpdir"
WebMock.disable_net_connect!
def Minitest.parallel_fork_number = 4
ENV["EDITOR"] ||= "vi"

require_relative "../lib/require"

module DeployTestMethods
  CMD_LOCAL = Cmd.method(:local)
  REQ_CALL = Req.method(:call)
end

developer_id_key = OpenSSL::PKey::EC.generate("prime256v1")
developer_id_name = OpenSSL::X509::Name.parse("CN=Developer ID Application")
developer_id_certificate = OpenSSL::X509::Certificate.new
developer_id_certificate.serial = 1
developer_id_certificate.version = 2
developer_id_certificate.subject = developer_id_name
developer_id_certificate.issuer = developer_id_name
developer_id_certificate.public_key = developer_id_key
developer_id_certificate.not_before = Time.now
developer_id_certificate.not_after = Time.now + 3600
developer_id_certificate.sign(developer_id_key, OpenSSL::Digest.new("SHA256"))
developer_id_password = "certificate-password"
developer_id_pkcs12 = OpenSSL::PKCS12.create(
  developer_id_password,
  "Developer ID Application",
  developer_id_key,
  developer_id_certificate,
)

[ BasePatch, Cloudflare, Instance ].each do |klass|
  klass.define_singleton_method(:puts) { |*| }
end

Cmd.define_singleton_method(:local) { |*, **| raise UnsafeTestOperation, "Cmd.local must be stubbed in deploy tests" }
Cmd.define_singleton_method(:ssh) { |*, **| raise UnsafeTestOperation, "Cmd.ssh must be stubbed in deploy tests" }
Cmd.define_singleton_method(:ssh_write) { |*, **| raise UnsafeTestOperation, "Cmd.ssh_write must be stubbed in deploy tests" }
Req.define_singleton_method(:call) { |*, **| raise UnsafeTestOperation, "Req.call must be stubbed in deploy tests" }
Net::SSH.define_singleton_method(:start) { |*, **| raise UnsafeTestOperation, "Net::SSH.start must be stubbed in deploy tests" }

{
  "BACKUP_ACCESS_KEY_ID" => "access",
  "BACKUP_BUCKET" => "backups",
  "BACKUP_ENDPOINT" => "https://storage.example.com",
  "BACKUP_SECRET_ACCESS_KEY" => "secret",
  "APPLE_ISSUER_ID" => "issuer",
  "APPLE_DEVELOPMENT_CERTIFICATE_BASE64" => [ developer_id_pkcs12.to_der ].pack("m0"),
  "APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD" => developer_id_password,
  "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64" => [ developer_id_pkcs12.to_der ].pack("m0"),
  "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD" => developer_id_password,
  "APPLE_DISTRIBUTION_CERTIFICATE_BASE64" => [ developer_id_pkcs12.to_der ].pack("m0"),
  "APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD" => developer_id_password,
  "APPLE_KEY_ID" => "key",
  "APPLE_KEY_SECRET_BASE64" => [ OpenSSL::PKey::EC.generate("prime256v1").to_pem ].pack("m0"),
  "APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_BASE64" => [ developer_id_pkcs12.to_der ].pack("m0"),
  "APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD" => developer_id_password,
  "APPLE_TEAM_ID" => "team",
  "CLOUDFLARE_TOKEN" => "cloudflare-token",
  "DB_NAME" => "app",
  "DEPLOY_PASSWORD" => "password",
  "DEPLOY_SSH_KEY" => "private-key",
  "DEPLOY_SSH_KEY_FINGERPRINT" => "fingerprint",
  "DEPLOY_SSH_KEY_PUB" => "public-key",
  "DEPLOY_USER" => "deploy",
  "DIGITAL_OCEAN_TOKEN" => "digital-ocean-token",
  "DOMAIN" => "example.com",
  "GITHUB_REPO" => "git@github.com:example/app.git",
  "GITHUB_TOKEN" => "github-token",
  "INSTANCE_REGION" => "test-region",
  "INSTANCE_SIZE" => "test-size",
  "test" => "true",
}.each { |key, value| ENV[key] = value }

module DeployTestIsolation
  def before_setup
    @deploy_test_dir = Dir.mktmpdir
    $cache = Cache.new(dir: File.join(@deploy_test_dir, "cache"))
    configure_apps_fixture
    Constants.instance_variable_set(:@ssh_key_path, File.join(@deploy_test_dir, "id_rsa"))
    Instance.clear
    Cloudflare.instance_variable_set(:@zone_id, nil)
    Subdomains.instance_variable_set(:@all, nil)
    DependenciesPatch.instance_variable_set(:@current_versions, nil)
    CertPatch.instance_variable_set(:@certificate, nil)
    super
  end

  def after_teardown
    FileUtils.rm_rf(@deploy_test_dir)
    Apps.reset
    super
  end

  private

  def configure_apps_fixture
    apps_root = File.join(@deploy_test_dir, "apps")
    project_path = File.join(apps_root, "apple", "App.xcodeproj")
    screenshot_path = File.join(apps_root, "screenshots", "ios.jpeg")
    FileUtils.mkdir_p(File.join(apps_root, "apple", "App", "Config"))
    FileUtils.mkdir_p(File.dirname(screenshot_path))
    FileUtils.mkdir_p(project_path)
    File.write(screenshot_path, "screenshot")
    File.write(
      File.join(apps_root, "config.json"),
      JSON.generate(
        build: "456",
        contactEmail: "reviewer@example.com",
        contactFirstName: "First",
        contactLastName: "Last",
        contactPhone: "+1 202 555 0100",
        copyright: "2026 Example",
        demoAccountName: "login",
        demoAccountPassword: "password",
        demoAccountRequired: true,
        description: "Description",
        keywords: "app",
        marketingUrl: "https://example.com",
        name: "App",
        notes: "Notes",
        primaryLocale: "en-US",
        promotionalText: "Promotional text",
        releaseType: "AFTER_APPROVAL",
        supportUrl: "https://example.com/support",
        targets: {
          apple: {
            ios: {
              archiveDestination: "generic/platform=iOS",
              bundleIdentifier: "org.example.app",
              platform: "IOS",
              project: project_path,
              scheme: "App",
              screenshots: [ { displayType: "APP_IPHONE_65", path: screenshot_path } ],
              simulatorDestination: "generic/platform=iOS Simulator",
              simulatorProduct: "Debug-iphonesimulator/App.app",
              simulators: { iphone: "iPhone", ipad: "iPad" },
            },
          },
          android: {},
        },
        version: "1.2.3",
        whatsNew: "Changes",
      ),
    )
    File.write(File.join(apps_root, "apple", "App", "Config", "ExportOptions.plist"), "plist")
    Apps.root = apps_root
    Apps.tmp_root = File.join(@deploy_test_dir, "artifacts")
  end
end

Minitest::Test.prepend(DeployTestIsolation)

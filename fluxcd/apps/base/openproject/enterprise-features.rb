# Every Enterprise feature known to the openproject-token gem bundled with this release counts
# as licensed. Nothing is replaced in the image, and the feature list comes from the running
# release's own gem, so new features need no update here.
Rails.application.config.to_prepare do
  missing = %i[allows_to? active? available_features] - EnterpriseToken.methods
  Rails.logger.warn("enterprise-features: EnterpriseToken no longer has #{missing.join(', ')}") if missing.any?

  EnterpriseToken.singleton_class.prepend(Module.new do
    def all_features = OpenProject::Token::FEATURES_PER_PLAN.values.reduce(Set.new, :|)
    def allows_to?(_feature) = true
    def active? = true
    def trial_only? = false
    def available_features = all_features
    def non_trialling_features = all_features
    def trialling?(_feature) = false
    def hide_banners? = true
    def user_limit = nil
  end)
end

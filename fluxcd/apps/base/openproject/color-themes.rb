# SysEggplant: the house palette as a preset in Administration -> Design, beside the built-in themes.
Rails.application.config.to_prepare do
  OpenProject::CustomStyles::ColorThemes.singleton_class.prepend(Module.new do
    def themes
      super + [{
        theme: "SysEggplant",
        colors: {
          "primary-button-color" => "#236144",
          "accent-color" => "#74ECBE",
          "header-bg-color" => "#310937",
          "main-menu-bg-color" => "#26062B",
          "main-menu-bg-selected-background" => "#3F1247"
        }
      }]
    end
  end)
end

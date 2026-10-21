# SysEggplant: the house palette as a preset in Administration -> Design, beside the built-in themes.
Rails.application.config.to_prepare do
  OpenProject::CustomStyles::ColorThemes.singleton_class.prepend(Module.new do
    def themes
      super + [{
        theme: "SysEggplant",
        colors: {
          "primary-button-color" => "#236144",
          "accent-color" => "#236144",
          "header-bg-color" => "#310937",
          "main-menu-bg-color" => "#26062B",
          "main-menu-bg-selected-background" => "#3F1247"
        }
      }]
    end
  end)

  # The dark theme swaps header and sidebar for Primer greys (custom_styles/_primer_color_mapping.erb);
  # this head hook renders after it and puts the eggplant back while SysEggplant is the active preset.
  unless defined?(SysEggplantDarkModeHook)
    class SysEggplantDarkModeHook < OpenProject::Hook::ViewListener
      CSS = <<~CSS.freeze
        [data-dark-theme=dark] {
          --header-bg-color: #310937;
          --header-border-bottom-color: #3F1247 !important;
          --main-menu-bg-color: #26062B;
          --main-menu-bg-selected-background: #3F1247;
          --main-menu-border-color: #3F1247;
          --accent-color: #74ECBE;
          --content-icon-color: #74ECBE;
        }
      CSS

      def view_layouts_base_html_head(_context = {})
        return unless CustomStyle.current&.theme == "SysEggplant"

        content_tag(:style, CSS.html_safe)
      end
    end
  end
end

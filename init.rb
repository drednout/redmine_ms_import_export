require 'redmine'

Redmine::Plugin.register :redmine_ms_import_export do
  name 'Redmine Ms Import Export plugin'
  author 'Alexei Romanoff'
  description 'Basic Import/Export from MS Project to Redmine and vice versa.'
  version '0.0.1'
  url 'https://github.com/drednout/redmine_ms_import_export'
  author_url 'http://www.facebook.com/alexei.romanoff'
  settings :default => {'tracker' => 'MsProject',  :partial => 'settings/ms_import_export_settings'}

  project_module :ms_importer_exporter do
    permission :ms_import_issues, :ms_import_export => [:new, :create]
  end

  menu :project_menu, :ms_import_export, { :controller => 'ms_import_export', :action => 'new' },
    :caption => 'MS Import/Export', :after => :new_issue, :param => :project_id

end

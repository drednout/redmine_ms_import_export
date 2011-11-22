class CreateMsProjectNames < ActiveRecord::Migration
  def self.up
    create_table :ms_project_names do |t|
      t.column :ms_project_name, :string
      t.column :redmine_project_id, :integer

      t.timestamps
    end
  end

  def self.down
    drop_table :ms_project_names
  end
end

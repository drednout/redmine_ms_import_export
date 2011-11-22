class CreateMsProjectTasks < ActiveRecord::Migration
  def self.up
    create_table :ms_project_tasks do |t|
      t.column :ms_uid, :integer
      t.column :ms_id, :integer
      t.column :redmine_issue_id, :integer
      t.column :start, :datetime
      t.column :finish, :datetime
      t.column :outline_level, :integer
      t.column :orig_outline_number, :string
      t.column :parent_task_id, :integer
      #see the table ms_project_names
      t.column :uniq_ms_project_id, :integer

      t.timestamps
    end
    add_index :ms_project_tasks, :ms_uid
    add_index :ms_project_tasks, :redmine_issue_id
    add_index :ms_project_tasks, :orig_outline_number
    add_index :ms_project_tasks, :uniq_ms_project_id
  end

  def self.down
    drop_table :ms_project_tasks
  end
end

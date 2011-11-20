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
    end
  end

  def self.down
    drop_table :ms_project_tasks
  end
end

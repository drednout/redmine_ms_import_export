# == Schema Information
#
# Table name: ms_project_tasks
#
#  id            :integer(4)      not null, primary key
#  ms_uid        :integer(4)
#  ms_id         :integer(4)
#  start         :datetime
#  finish        :datetime
#  outline_level :integer(4)
#  orig_outline_number :string
#  parent_task_id  :integer(4)
# 

class MsProjectTask < ActiveRecord::Base
  unloadable
end

require 'xml'

class MsImportExportController < ApplicationController
  unloadable

  #before_filter :find_project, :authorize, :only => [:new, :create]

  def new
    @project = Project.find(params[:project_id])
  end

  def upload
    @project_tasks = []
    @project_resources = []
    @project_assignments = []
    uploaded_file = params[:upload][:file_for_upload]

    parser = XML::Parser.string(uploaded_file.read())
    doc = parser.parse
    ns = 'project'
    doc.root.namespaces.default_prefix = ns

    resources = doc.find("//#{ns}:Resource", '#{ns}:http://schemas.microsoft.com/project')
    resources.each do |res|
        user_record = {}
        ['UID', 'ID', 'Name', 'Group'].each do |res_attr|
            xpath_attr = res.find(ns + ":" +res_attr)
            if not xpath_attr.empty?
                user_record[res_attr] = xpath_attr.first.content
            end
        end
        @project_resources.push(user_record)
    end

    tasks = doc.find("//#{ns}:Task", '#{ns}:http://schemas.microsoft.com/project')
    tasks.each do |task|
        task_record = {}
        ['UID', 'ID', 'Start', 'Finish', 
         'Name', 'PercentComplete', 'OutlineLevel',
          'PercentComplete', 'Milestone'].each do |task_attr|
            xpath_attr = task.find(ns + ":" +task_attr)
            if not xpath_attr.empty?
                task_record[task_attr] = xpath_attr.first.content
            end
        end
        task_predcessors = []
        predcessors = task.find(ns + ":" + "PredecessorLink")
        predcessors.each do |predcessor|
            predcessor_record = {}
            predcessor.each_element do |pred_element|
                if pred_element.name == "PredecessorUID"
                    predcessor_record[pred_element.name] = pred_element.content
                end
            end
            task_predcessors.push(predcessor_record)
        end
        task_record["Predecessors"] = task_predcessors
        @project_tasks.push(task_record)
    end

    assignments = doc.find("//#{ns}:Assignment", '#{ns}:http://schemas.microsoft.com/project')
    assignments.each do |assign|
        assign_record = {}
        ['UID', 'TaskUID', 'ResourceUID'].each do |assign_attr|
            xpath_attr = assign.find(ns + ":" +assign_attr)
            if not xpath_attr.empty?
                assign_record[assign_attr] = xpath_attr.first.content
            end
        end
        @project_assignments.push(assign_record)
    end
  end
end

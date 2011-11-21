require 'xml'

class MsImportExportController < ApplicationController
  unloadable

  #before_filter :find_project, :authorize, :only => [:new, :create]

  def new
    @project = Project.find(params[:project_id])
  end

  def upload
    @project = Project.find(params[:project_id])
    @tracker = Tracker.find(:first, :conditions => [ "name = ?", "MS Project"])

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
        ['UID', 'ID', 'Name', 'Group', 'EmailAddress'].each do |res_attr|
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
         'Milestone', 'Notes', 'OutlineNumber'].each do |task_attr|
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

    self.save_imported_tasks()
  end

  def get_parent_outline_number(outline_number)
    outline_array = outline_number.split(".")
    return nil if outline_array.size == 1
    outline_array.pop()
    return outline_array.join(".")
  end

  def save_imported_tasks
    logger.info("save_imported: @project is #{@project}")
    @project_tasks.each do |task|
      is_new_task = false
      ms_task =  MsProjectTask.find_by_ms_uid(task['UID']) 
      if ms_task.nil?
        is_new_task = true
        ms_task = MsProjectTask.new
      end
      if task['Name'].nil?
        logger.error "save_imported_tasks: cant's save ms task " +\
                      "with UID=#{task['UID']}, because task Name is nil"
        next
      end

      ms_task.ms_uid = task['UID']
      ms_task.ms_id = task['ID']
      ms_task.outline_level = task['OutlineLevel']
      ms_task.start = task['Start']
      ms_task.finish = task['Finish']
      ms_task.orig_outline_number = task['OutlineNumber']

      if is_new_task
        issue = Issue.new
      else
        issue = Issue.find(ms_task.redmine_issue_id)
        if issue.nil?
          raise "Fucking redmine issue error"
        end
      end
      issue.project = @project
      issue.author = User.current
      issue.subject = task['Name'].slice(0, 255)
      issue.description = task['Notes']
      issue.tracker_id = @tracker.id
      issue.start_date = ms_task.start
      issue.due_date = ms_task.finish
      #issue.done_ratio = task['PercentComplete']

      #TODO: notify user somehow about errors when importing
      issue_save_res = issue.save
      logger.debug "save_imported_tasks: issue_save_res is #{issue_save_res}"
      logger.debug "save_imported_tasks: issue.errors are #{issue.errors.full_messages}"
      if not issue_save_res
        #TODO: raise normal redmine exception
        logger.error "save_imported_tasks: cant's save ms task " +\
                      "with UID=#{task['UID']}  as redmine issue, Name is `#{task['Name']}` "
        next
      end

      ms_task.redmine_issue_id = issue.id if is_new_task
      ms_task.save
      if not issue_save_res
        #TODO: raise normal redmine exception
        logger.error "save_imported_tasks: cant's save ms task " +\
                      "with UID=#{task['UID']}, Name is `#{task['Name']}` "
        next
      end

      parent_outline_number = self.get_parent_outline_number(task['OutlineNumber'])
      if parent_outline_number
        logger.debug("save_imported_tasks: parent_outline_number is #{parent_outline_number}")
        parent_ms_task = MsProjectTask.find_by_orig_outline_number(parent_outline_number)
        ms_task.parent_task_id = parent_ms_task.ms_uid
        issue.parent_issue_id = parent_ms_task.redmine_issue_id
        #TODO: avoiding of double saving
        issue.save
        ms_task.save
      end

      if task.has_key?("Predecessors") and not task["Predecessors"].empty?
        task["Predecessors"].each do |pred_task_from_xml|
          logger.debug "save_imported_tasks: First task predcessors is #{pred_task_from_xml}"
          pred_ms_task = MsProjectTask.find_by_ms_uid(pred_task_from_xml["PredecessorUID"])
          pred_redmine_issue = Issue.find(pred_ms_task.redmine_issue_id)
          logger.debug "save_imported_tasks: pred_redmine_issue is #{pred_redmine_issue}"
          relation = IssueRelation.new
          relation.issue_from = pred_redmine_issue
          relation.issue_to = issue
          relation.relation_type = IssueRelation::TYPE_PRECEDES
          logger.debug "save_imported_tasks: relation.issue_from is #{relation.issue_from.id}, issue_to is #{relation.issue_to.id}"
          find_res = IssueRelation.find(:first, :conditions => 
                                        ["issue_from_id = ? AND issue_to_id = ? AND relation_type = ?",
                                         pred_redmine_issue.id, issue.id,
                                         IssueRelation::TYPE_PRECEDES])
          logger.debug "save_imported_tasks: find_res is '#{find_res}'"
          relation.save if find_res.nil?
          logger.debug "save_imported_tasks: relation.errors are #{relation.errors.full_messages}"
        end
      end

    end
  end
end

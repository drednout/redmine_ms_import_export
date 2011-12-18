require 'xml'

class MsImportExportController < ApplicationController
  unloadable

  #before_filter :find_project, :authorize, :only => [:new, :create]

  def new
    @project = Project.find(params[:project_id])
  end

  def get_tracker_info
    top_tracker = Setting.plugin_redmine_ms_import_export['tracker_top']    
    tracker_1 = Setting.plugin_redmine_ms_import_export['tracker_1']    
    tracker_2 = Setting.plugin_redmine_ms_import_export['tracker_2']    
    tracker_others = Setting.plugin_redmine_ms_import_export['tracker_others']    
    #specifies the tracker which will be used for imported task in depend 
    #of OutlineLevel(hash's key). All tasks with OutlineLevel > 2 will be imported 
    #to tracker @tracker_others
    tracker_map = {
      1 => top_tracker,
      2 => tracker_1,
      3 => tracker_2,
    }
    return tracker_map, tracker_others
  end

  def upload
    @project = Project.find(params[:project_id])

    @project_tasks = []
    @project_resources = []
    @resource_hash_by_uid = {}
    @project_assignments = []
    @assignment_hash_by_taskuid = {}
    uploaded_file = params[:upload][:file_for_upload]
    uploaded_file_path = Rails.root.join('public', 'uploads', uploaded_file.original_filename)
    File.open(uploaded_file_path, 'w') do |f|
      f.write(uploaded_file.read)
    end

    parser = XML::Parser.file(uploaded_file_path)
    doc = parser.parse
    ns = 'project'
    doc.root.namespaces.default_prefix = ns

    #TODO: refactoring: variable schema
    xpath_project_name = doc.find("/#{ns}:Project/#{ns}:Name", 
                                  '#{ns}:http://schemas.microsoft.com/project')
    #TODO: check project name correctness
    @ms_project_name = xpath_project_name[0].first.content


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
        @resource_hash_by_uid[user_record['UID']] = user_record
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

        task_uid = assign_record['TaskUID']
        if not @assignment_hash_by_taskuid.has_key?(task_uid)
          @assignment_hash_by_taskuid[task_uid] = []
        end
       @assignment_hash_by_taskuid[task_uid].push(assign_record)
    end
    logger.debug "upload: @assignment_hash_by_taskuid is #{@assignment_hash_by_taskuid.to_xml}"
    self.save_imported_tasks()
  end

  def get_parent_outline_number(outline_number)
    outline_array = outline_number.split(".")
    return nil if outline_array.size == 1
    outline_array.pop()
    return outline_array.join(".")
  end

  def get_assigned_redmine_user(task)
      return nil unless @assignment_hash_by_taskuid.has_key?(task['UID'])
      assign_list = @assignment_hash_by_taskuid[task['UID']]
      logger.info "get_assigned_redmine_user: assignment capacity is #{assign_list.size}"
      #we can assign only one person per task in redmine, do this for first assignee
      assign_record = assign_list.first
      resource_record = @resource_hash_by_uid[assign_record['ResourceUID']]
      if resource_record.nil?
        logger.warn "Can't find resource record with UID #{assign_record['ResourceUID']}"
        return nil
      end
      redmine_user = User.find_by_mail(resource_record['EmailAddress'])
      if redmine_user.nil?
        logger.info "Can't find redmine user with email #{resource_record['EmailAddress']}"
      else
        return redmine_user
      end
      assign_field_name = Setting.plugin_redmine_ms_import_export['assign_custom_field']    
      if assign_field_name.nil? or assign_field_name.empty?
        logger.error "Please specify custom field for assignment users in plugin settings"
        return nil 
      end
      custom_field = CustomField.find_by_name(assign_field_name)
      logger.debug "custom_field is #{custom_field}"
      if custom_field.class.name != "UserCustomField"
        logger.error "Invalid custom field type #{custom_field.type}"
        return nil
      end
      custom_values = CustomValue.find(:all, :conditions => 
                                      ["custom_field_id = ?", custom_field.id])
      custom_values.each do |custom_value|
        if custom_value.value == resource_record['EmailAddress']
          redmine_user = User.find_by_id(custom_value.customized_id)
          logger.debug "get_assigned_redmine_user: user found by custom field: #{redmine_user}"
          return redmine_user
        end
      end
      return nil
  end

  def save_imported_tasks
    ms_project = MsProjectName.find_by_ms_project_name(@ms_project_name)
    tracker_map, tracker_others = self.get_tracker_info
    if ms_project.nil?
      ms_project = MsProjectName.create(:ms_project_name => @ms_project_name, 
                                        :redmine_project_id => @project.id)
    end
    logger.info("save_imported: @project is #{@project}")
    @project_tasks.each do |task|
      is_new_task = false
      ms_task = MsProjectTask.find(:first, :conditions => 
                                   ["uniq_ms_project_id = ? AND ms_uid = ?",
                                    ms_project.id, task['UID']])
      if ms_task.nil?
        is_new_task = true
        ms_task = MsProjectTask.new
      end
      if task['Name'].nil?
        logger.warn "save_imported_tasks: name of ms task " +\
                    "with UID=#{task['UID']} is nil, replaced with default value"
        task['Name'] = 'TODO: Empty name'
      end

      outline_level = task['OutlineLevel'].to_i()
      logger.debug("save_imported_tasks: outline_level is #{outline_level}")
      logger.debug("save_imported_tasks: tracker_map is #{tracker_map}")
      if tracker_map.has_key?(outline_level)
        tracker_name = tracker_map[outline_level] 
      else
        tracker_name = tracker_others
      end
      logger.debug("save_imported_tasks: tracker_name is #{tracker_name}")
      @tracker = Tracker.find(:first, :conditions => [ "name = ?", tracker_name])
      if @tracker.nil?
        flash[ :error ] = "Invalid tracker name #{tracker_name} in plugin settings. Please fix it and try again."
      end
      if flash[ :error ]
        render( { :action => :new } )
        flash.delete( :error )                                                                                            
        return                                                                                                            
      end


      ms_task.ms_uid = task['UID']
      ms_task.ms_id = task['ID']
      ms_task.outline_level = task['OutlineLevel']
      ms_task.start = task['Start']
      ms_task.finish = task['Finish']
      ms_task.orig_outline_number = task['OutlineNumber']
      ms_task.uniq_ms_project_id = ms_project.id

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
      issue.done_ratio = task['PercentComplete'] if task['PercentComplete']

      assigned_user = get_assigned_redmine_user(task)
      issue.assigned_to = assigned_user unless assigned_user.nil?



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
        #parent_ms_task = MsProjectTask.find_by_orig_outline_number(parent_outline_number)
        parent_ms_task = MsProjectTask.find(:first, :conditions => 
                                            ["uniq_ms_project_id = ? AND orig_outline_number = ?",
                                             ms_project.id, parent_outline_number])
        if not parent_ms_task.nil?
          ms_task.parent_task_id = parent_ms_task.ms_uid
          issue.parent_issue_id = parent_ms_task.redmine_issue_id
          #TODO: avoiding of double saving
          issue.save
          ms_task.save
        end
      end

      if task.has_key?("Predecessors") and not task["Predecessors"].empty?
        task["Predecessors"].each do |pred_task_from_xml|
          logger.debug "save_imported_tasks: First task predcessors is #{pred_task_from_xml}"
          #pred_ms_task = MsProjectTask.find_by_ms_uid(pred_task_from_xml["PredecessorUID"])
          pred_ms_task = MsProjectTask.find(:first, :conditions => 
                                            ["uniq_ms_project_id = ? AND ms_uid = ?",
                                             ms_project.id, pred_task_from_xml['PredecessorUID']])
          if pred_ms_task.nil?
            logger.error "save_imported_tasks: can't find ms predcessor with PredecessorUID" +\
                         " #{pred_task_from_xml['PredecessorUID']} when importing task with UID #{task['UID']}"
            next
          end
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

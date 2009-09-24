class DashboardController < ApplicationController
  helper :shifts
  helper :data_entries
  helper :punch_clocks

  def index
    # for lists of shifts
    #@active_shifts = Shift.all.select{|s| s.report and !s.submitted? and current_department.locations.include?(s.location)}.sort_by(&:start)
    #@upcoming_shifts = current_user.shifts.select{|shift| shift.scheduled? and shift.end > Time.now and !(shift.submitted?) and @department.locations.include?(shift.location)}.sort_by(&:start)[0..3]
#    @shift = Shift.new

    @active_shifts = Shift.find(:all, :conditions => {:signed_in => true, :department_id => current_department.id}, :order => :start)
    @upcoming_shifts = Shift.find(:all, :conditions => ['"user_id" = ? and "end" > ? and "department_id" = ? and "scheduled" = ? and "active" = ?', current_user.id, Time.now, current_department.id, true, true], :order => :start, :limit => 5)
    @subs_you_requested = SubRequest.find(:all, :conditions => ["end > ? AND user_id = ?", Time.now, current_user.id]).sort_by(&:start)
    @subs_you_can_take = current_user.available_sub_requests([@department]).select{|sub| sub.end > Time.now}.sort_by(&:start)

    @most_recent_payform= current_user.payforms.sort_by(&:date).last
    @watched_objects = current_user.user_config.watched_data_objects.split(", ").map{|id| DataObject.find(id)}.flatten

    @dept_start_hour = current_department.department_config.schedule_start / 60
    @dept_end_hour = current_department.department_config.schedule_end / 60
    @hours_per_day = (@dept_end_hour - @dept_start_hour)
    @dept_start_minute = @dept_start_hour * 60
    @dept_end_minute = @dept_end_hour * 60
    @loc_groups = current_user.user_config.view_loc_groups
    @display_unscheduled_shifts = @department.department_config.unscheduled_shifts
    @time_increment = current_department.department_config.time_increment
    @blocks_per_hour = 60/@time_increment.to_f
  end

end

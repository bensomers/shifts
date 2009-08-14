class TimeSlot < ActiveRecord::Base
  belongs_to :location
  belongs_to :calendar
  belongs_to :repeating_event
  has_many :shifts, :through => :location
  before_save :set_active

  validates_presence_of :start, :end, :location_id
  validate :start_less_than_end
  validate :is_within_calendar

  named_scope :active, lambda {{:conditions => {:active => true}}}
  named_scope :in_locations, lambda {|loc_array| {:conditions => { :location_id => loc_array }}}
  named_scope :in_location, lambda {|location| {:conditions => { :location_id => location }}}
  named_scope :on_days, lambda {|start_day, end_day| { :conditions => ["#{:start.to_sql_column} >= #{start_day.beginning_of_day.utc.to_sql} and #{:start.to_sql_column} < #{end_day.end_of_day.utc.to_sql}"]}}
  named_scope :on_day, lambda {|day| { :conditions => ["#{:start.to_sql_column} >= #{day.beginning_of_day.utc.to_sql} AND #{:start.to_sql_column} < #{day.beginning_of_day.utc.to_sql}"]}}
  named_scope :after_now, lambda {{:conditions => ["#{:end} >= #{Time.now.utc.to_sql}"]}}


  #This method creates the multitude of shifts required for repeating_events to work
  #in order to work efficiently, it makes a few GIANT sql insert calls
  def self.make_future(end_date, cal_id, r_e_id, days, loc_ids, start_time, end_time, active, wipe)
    #We need several inner arrays with one big outer one, b/c sqlite freaks out if the sql insert call is too big
    outer_make = []
    inner_make = []
    outer_test = []
    inner_test = []
    diff = end_time - start_time
    #Take each location and day and build an array containing the pieces of the sql query
    loc_ids.each do |loc_id|
      days.each do |day|
        seed_start_time = start_time
        seed_end_time = end_time
        while seed_end_time <= end_date
          seed_start_time = seed_start_time.next(day)
          seed_end_time = seed_start_time + diff
          inner_test.push "(location_id = #{loc_id.to_sql} AND (active = #{true.to_sql} OR calendar_id = #{cal_id.to_sql}) AND start <= #{seed_end_time.utc.to_sql} AND end >= #{seed_start_time.utc.to_sql})"
          inner_make.push "#{loc_id.to_sql}, #{cal_id.to_sql}, #{r_e_id.to_sql}, #{seed_start_time.utc.to_sql}, #{seed_end_time.utc.to_sql}, #{Time.now.utc.to_sql}, #{Time.now.utc.to_sql}, #{active.to_sql}"
          #Once the array becomes big enough that the sql call will insert 450 rows, start over w/ a new array
          #without this bit, sqlite freaks out if you are inserting a larger number of rows. Might need to be changed
          #for other databases (it can probably be higher for other ones I think, which would result in faster execution)
        if inner_make.length > 450
          outer_make.push inner_make
          inner_make = []
          outer_test.push inner_test
          inner_test = []
        end
        end
        #handle leftovers or the case where there are less than 450 rows to be inserted
      outer_make.push inner_make
      outer_test.push inner_test
      end
    end
    #for each set of rows to be inserted, insert them, all within a transaction for speed's sake
    if wipe
        outer_test.each do |s|
          TimeSlot.delete_all(s.join(" OR "))
        end
        outer_make.each do |s|
          sql = "INSERT INTO time_slots ('location_id', 'calendar_id', 'repeating_event_id', 'start', 'end', 'created_at', 'updated_at', 'active') SELECT #{s.join(" UNION ALL SELECT ")};"
          ActiveRecord::Base.connection.execute sql
        end
      return false
    else
      out = []
        outer_test.each do |s|
          out += TimeSlot.find(:all, :conditions => [s.join(" OR ")])
        end
      if out.empty? || !active
          outer_make.each do |s|
            sql = "INSERT INTO time_slots ('location_id', 'calendar_id', 'repeating_event_id', 'start', 'end', 'created_at', 'updated_at', 'active') SELECT #{s.join(" UNION ALL SELECT ")};"
            ActiveRecord::Base.connection.execute sql
          end
        return false
      end
      return out.collect{|t| "The timeslot "+t.to_message_name+" conflicts. Use wipe to fix."}.join(",")
    end
  end

  def self.check_for_conflicts(time_slots)
    if time_slots.empty?
      ""
    else
      TimeSlot.find(:all, :conditions => [time_slots.collect{|t| "(location_id = #{t.location_id.to_sql} AND active = #{true.to_sql} AND start <= #{t.end.utc.to_sql} AND end >= #{t.start.utc.to_sql})"}.join(" OR ")]).collect{|t| "The timeslot "+t.to_message_name+" conflicts. Use wipe to fix."}.join(",")
    end
  end

  def duration
    self.end-self.start
  end

  def to_s
    self.location.short_name + ', ' + self.start.to_s(:am_pm_long) + " - " + self.end.to_s(:am_pm_long)
  end

  def to_message_name
    "in "+self.location.short_name + ' from ' + self.start.to_s(:am_pm_long_no_comma) + " to " + self.end.to_s(:am_pm_long_no_comma)
  end

  private

  def set_active
    self.active = self.calendar.active
    return true
  end

  def start_less_than_end
    errors.add(:start, "must be earlier than end time") if (self.end <= start)
  end

  def is_within_calendar
    unless self.calendar.default
      errors.add_to_base("Repeating event start and end dates must be within the range of the calendar!") if self.start < self.calendar.start_date || self.end > self.calendar.end_date
    end
  end
end

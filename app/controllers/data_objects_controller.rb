class DataObjectsController < ApplicationController
  #User admin methods will need to be rewritten in move to other codebase
  
  def index   
    @data_objects = get_allowed_data_objects
    @group_type_options = options_for_group_type
    @group_by_options = []
    if params[:view_options]
      @selected_type = params[:view_options][:group_type]
      if params[:view_options][:group_by]
        unless (@selected_by = params[:view_options][:group_by]).blank?
          @data_objects = @selected_type.classify.constantize.find(@selected_by).data_objects
        end
      end
      @group_by_options = options_for_group_by(@selected_type)
    end
    @data_types = @data_objects.group_by &:data_type
  end
  
  def show
    @data_object = DataObject.find(params[:id])   
    @data_type = @data_object.data_type
  end
  
  def new
    @data_object = DataObject.build({:data_type_id => params[:data_type_id]})
    @data_type = DataType.find(params[:data_type_id])
  end
  
  def create
    @data_object = DataObject.new(params[:data_object])
    @data_object.data_type_id = params[:data_object][:data_type_id]
    if @data_object.save
      flash[:notice] = "Successfully created data object."
      redirect_to data_objects_path
    else
      render :action => 'new'
    end
  end
  
  def edit
    @data_object = DataObject.find(params[:id])
    @data_type = @data_object.data_type
  end
  
  def update
    @data_object = DataObject.find(params[:id])
    if @data_object.update_attributes(params[:data_object])
      flash[:notice] = "Successfully updated data object."
      redirect_to @data_object
    else
      render :action => 'edit'
    end
  end
  
  def destroy
    @data_object = DataObject.find(params[:id])
    @data_object.destroy
    flash[:notice] = "Successfully destroyed data object."
    redirect_to data_objects_url
  end
    
private

  # Returns all the data objects that the user is permitted to administer
  def get_allowed_data_objects
    unless (@loc_groups = current_user.loc_groups_to_admin(@department)).empty?
      return @loc_groups.map{|lg| DataObject.by_location_group(lg)}.flatten    
    end
    return @department.data_objects if current_user.is_admin_of?(@department)
    flash[:error] = "You do not have the permissions necessary to view any
                    data objects."
    redirect_to access_denied_path
  end
  
  def options_for_group_type
    options = [["Location","locations"],["Location Group","loc_groups"]]
    if current_user.is_admin_of?(@department)
      options.push(["Data type", "data_types"], ["Department", "departments"])
    end
  end 
  
  def options_for_group_by(group_type)
    return [] if group_type == "departments"
    @options = @department.send(group_type)
    if group_type == "locations" || group_type == "loc_groups" 
      @options.reject!{|opt| !current_user.permission_list.include?(opt.admin_permission)}
    end
    @options.map{|t| [t.name, t.id]} << []
  end
    
    
end

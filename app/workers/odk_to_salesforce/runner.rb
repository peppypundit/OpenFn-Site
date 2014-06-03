module OdkToSalesforce
  ##
  # The runner sets in motion the omport process. It is fed a hash of child
  # items (leafs on the dependency hash) and recursively imports up the
  # dependencies tree.
  #
  # TODO: validate before calling parent.
  class Runner

    ##
    # Takes a relationships hash generated by Salesforce class
    def initialize relationships
      @relationships = relationships
      @rf = Restforce.new
    end

    # - data: hash of salesforce data to be imported in the form:
    #
    #   { object: { field: value, field_2: [value_1, value_2 ] } }
    def run(sf_object, data)
      node = @relationships[sf_object.to_sym]
      parent_objects = []
      constraints = data[node[:name].to_sym]

      if create_parents_first?(node, data)
        puts "-> find or create parents for #{node[:name]}"
        node[:parents].each do |parent_node|
          if data.has_key?(parent_node.to_sym)
            parent_objects << run(parent_node, data)
          end
        end
      else
        puts "-> find or create #{node[:name]}"
        thing = find_or_create_one_or_many(node[:name], constraints)
        return thing
      end

      if parent_objects.include?(false)
        return false
      else
        parent_objects.each do |parent_object|
          parent_attributes = parent_object["attributes"]
          constraints[parent_attributes["type"].to_sym] = parent_object["Id"]

        end
        return find_or_create_one_or_many(node[:name], constraints)
      end
    end

    private

    ##
    # If any of the fields is an array 
    #
    #  { field: [value1, value2] }
    #
    # then we must assume they all are. In this case, 
    # we iterate over the first array and create a flat hash of 
    # constraints which we then pass to find_or_create on eachiterations.
    def find_or_create_one_or_many(object_name, constraints)
      if constraints.flatten.any? { |e| e.kind_of?(Array) }
        success_array = []     
        constraints.flatten.select { |e| e.kind_of?(Array)}[0].each_with_index do |c, i|
          flat_constraints = {}
          constraints.each do |k,v|
            # only iterate on arrays, otherwise make value the same for all
            if v.kind_of?(Array)
              flat_constraints[k] = v[i] 
            else
              flat_constraints[k] = v
            end
          end
          success_array << find_or_create(object_name, flat_constraints)
        end
        return success_array
      else
        return find_or_create(object_name, constraints)
      end
    end

    ##
    # Checks if to go up the tree or continue creating current element
    #
    # NOTE: the approach being used here is extremely naive: it will only
    # check if the mapping lists one of the object's parents, and proceed if
    # true. It is up to the user to not screw stuff up.
    def create_parents_first?(node, data)
      mapping_includes_parents = false
      has_parents = !node[:parents].empty? 
      if has_parents
        node[:parents].each do |parent|
          if data.has_key?(parent.to_sym) 
            mapping_includes_parents = true 
          end
        end
      end

      has_parents && mapping_includes_parents
    end

    def find_or_create(object_name, constraints)
      sf_object = find(object_name, constraints)
      puts "-> found #{object_name}, #{sf_object["Id"]}".magenta if !sf_object.nil?

      if sf_object.nil?
        puts "-> no #{object_name} fitting constraints"
        begin
          sf_id = create(object_name, constraints)
          sf_object = find(object_name, { Id: sf_id })
          sf_object = false if sf_object.nil?
        rescue 
          sf_object = false
        end
      end

      sf_object
    end

    def find(object_name, constraints)
      and_or_or = "AND"
      # if applicable, we want only to search by unique identifier fields
      has_uniques = false
      unique_constraints = only_unique_fields_if_any(object_name, constraints)

      if unique_constraints[0]
        has_uniques = true
        and_or_or = "OR"
        constraints = unique_constraints[1]
      end

      begin
        query_string = "SELECT Id FROM #{object_name} WHERE "
        constraints.each do |k, v|
          quote = "'" 
          if v.kind_of?(String)
            quote = "" if hey_is_this_string_a_number?(v)
          end
          query_string += "#{k} = #{quote}#{v}#{quote} #{and_or_or} " if not v.nil?
        end
        # remove trailing space and AND
        query_string = query_string[0..-6] if and_or_or == "AND"
        query_string = query_string[0..-5] if and_or_or == "OR"

        @rf.query(query_string)["records"].first
      rescue Exception => e  
        puts "-> something wrong in Salesforce query:".red
        puts e.message  
        return nil
      end
    end

    ##
    # If any of the field given are unique identifiers, return a hash of only
    # those fields.
    def only_unique_fields_if_any(object_name, constraints)
      uniques = {}       
      has_uniques = false
      constraints.each do |k, v|
        if @relationships[object_name.to_sym][:uniques].include?(k.to_s)
          has_uniques = true
          uniques[k] = v
        end
      end

      uniques = constraints if uniques.empty?
      return [has_uniques, uniques]
    end

    def hey_is_this_string_a_number?(string)
      if ((string =~ /^\d+(.\d+)?$/) or (string =~ /^\d+$/))
        return true
      else
        return false
      end
    end

    def create(object_name, constraints)
      response = @rf.create(object_name, constraints)
      if !response
        puts "-> Failed to create #{object_name}, on #{constraints}".red if !response
      else
        puts "-> created new #{object_name}, #{response["Id"]}".green.bold
      end
      response
    end
  end
end

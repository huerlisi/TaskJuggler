#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ReportBase.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010, 2011
#               by Chris Schlaeger <chris@linux.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

class TaskJuggler

  # This is the abstract base class for all kinds of reports. The derived
  # classes must implement the generateIntermediateFormat function as well as
  # the to_* members.
  class ReportBase

    def initialize(report)
      @report = report
      @project = report.project
    end

    # Convenience function to access a report attribute
    def a(attribute)
      @report.get(attribute)
    end

    def generateIntermediateFormat
      query = @report.project.reportContexts.last.query
      %w( header left center right footer
          prolog headline caption epilog ).each do |name|
        next unless (text = a(name))

        text.setQuery(query)
      end
    end

    def to_html
      raise 'This function must be overriden by derived classes.'
    end

    def to_csv
      raise 'This function must be overriden by derived classes.'
    end

    # Take the complete task list and remove all tasks that are matching the
    # hide expression, the rollup Expression or are not a descendent of
    # taskRoot. In case resource is not nil, a task is only included if
    # the resource is allocated to it in any of the reported scenarios.
    def filterTaskList(list_, resource, hideExpr, rollupExpr, openNodes)
      list = PropertyList.new(list_)
      if (taskRoot = a('taskRoot'))
        # Remove all tasks that are not descendents of the taskRoot.
        list.delete_if { |task| !task.isChildOf?(taskRoot) }
      end

      if resource
        # If we have a resource we need to check that the resource is allocated
        # to the tasks in any of the reported scenarios within the report time
        # frame.
        list.delete_if do |task|
          delete = true
          a('scenarios').each do |scenarioIdx|
            iv = Interval.new(a('start'), a('end'))
            if task.hasResourceAllocated?(scenarioIdx, iv, resource)
              delete = false
              break;
            end
          end
          delete
        end
      end

      standardFilterOps(list, hideExpr, rollupExpr, openNodes, resource,
                        taskRoot)
    end

    # Take the complete resource list and remove all resources that are matching
    # the hide expression, the rollup Expression or are not a descendent of
    # resourceRoot. In case task is not nil, a resource is only included if
    # it is assigned to the task in any of the reported scenarios.
    def filterResourceList(list_, task, hideExpr, rollupExpr, openNodes)
      list = PropertyList.new(list_)
      if (resourceRoot = a('resourceRoot'))
        # Remove all resources that are not descendents of the resourceRoot.
        list.delete_if { |resource| !resource.isChildOf?(resourceRoot) }
      end

      if task
        # If we have a task we need to check that the resources are assigned
        # to the task in any of the reported scenarios.
        iv = Interval.new(a('start'), a('end'))
        list.delete_if do |resource|
          delete = true
          a('scenarios').each do |scenarioIdx|
            if task.hasResourceAllocated?(scenarioIdx, iv, resource)
              delete = false
              break;
            end
          end
          delete
        end
      end

      standardFilterOps(list, hideExpr, rollupExpr, openNodes, task,
                        resourceRoot)
    end

    private

    def generateHtmlTableFrame
      table = XMLElement.new('table', 'class' => 'tj_table_frame',
                                      'cellspacing' => '1')

      # Headline box
      if a('headline')
        table << generateHtmlTableRow do
          td = XMLElement.new('td')
          td << (div = XMLElement.new('div', 'class' => 'tj_table_headline'))
          div << a('headline').to_html
          td
        end
      end

      table
    end

    def generateHtmlTableRow
      XMLElement.new('tr') << yield
    end

    # Convert the RichText object _name_ into a HTML form.
    def rt_to_html(name)
      return unless a(name)

      a(name).sectionNumbers = false
      a(name).to_html
    end

    # This function implements the generic filtering functionality for all kinds
    # of lists.
    def standardFilterOps(list, hideExpr, rollupExpr, openNodes, scopeProperty,
                          root)
      # Make a copy of the current Query.
      query = @project.reportContexts.last.query.dup
      query.scopeProperty = scopeProperty

      # Remove all properties that the user wants to have hidden.
      if hideExpr
        list.delete_if do |property|
          query.property = property
          hideExpr.eval(query)
        end
      end

      # Remove all children of properties that the user has rolled-up.
      if rollupExpr || openNodes
        list.delete_if do |property|
          parent = property.parent
          delete = false
          while (parent)
            query.property = parent
            # If openNodes is not nil, only the listed nodes will be unrolled.
            # If openNodes is nil, only the nodes that match rollupExpr will
            # not be unrolled.
            if (openNodes && !openNodes.include?([ parent, scopeProperty ])) ||
               (!openNodes && rollupExpr.eval(query))
              delete = true
              break
            end
            parent = parent.parent
          end
          delete
        end
      end

      # Re-add parents in tree mode
      if list.treeMode?
        parents = []
        list.each do |property|
          parent = property
          while (parent = parent.parent)
            parents << parent unless list.include?(parent) ||
                                     parents.include?(parent)
            break if parent == root
          end
        end
        list.append(parents)
      end

      list
    end

    # This function converts number to strings that may include a unit. The
    # unit is determined by @loadUnit. In the automatic modes, the shortest
    # possible result is shown and the unit is always appended. _value_ is the
    # value to convert. _factors_ determines the conversion factors for the
    # different units.
    # TODO: Delete when all users have been migrated to use Query!
    def scaleValue(value, factors)
      loadUnit = a('loadUnit')
      numberFormat = a('numberFormat')

      if loadUnit == :shortauto || loadUnit == :longauto
        # We try all possible units and store the resulting strings here.
        options = []
        # For each of the units we can define a maximum value that the value
        # should not exceed. A maximum of 0 means no limit.
        max = [ 60, 48, 0, 8, 24, 0 ]

        i = 0
        shortest = nil
        factors.each do |factor|
          scaledValue = value * factor
          str = numberFormat.format(scaledValue)
          # We ignore results that are 0 or exceed the maximum. To ensure that
          # we have at least one result the unscaled value is always taken.
          if (factor != 1.0 && scaledValue == 0) ||
             (max[i] != 0 && scaledValue > max[i])
            options << nil
          else
            options << str
          end
          i += 1
        end

        # Default to days in case they are all the same.
        shortest = 2
        # Find the shortest option.
        6.times do |j|
          shortest = j if options[j] &&
                          options[j].length < options[shortest].length
        end

        str = options[shortest]
        if loadUnit == :longauto
          # For the long units we handle singular and plural properly. For
          # English we just need to append an 's', but this code will work for
          # other languages as well.
          units = []
          if str == "1"
            units = %w( minute hour day week month year )
          else
            units = %w( minutes hours days weeks months years )
          end
          str += ' ' + units[shortest]
        else
          str += %w( min h d w m y )[shortest]
        end
      else
        # For fixed units we just need to do the conversion. No unit is
        # included.
        units = [ :minutes, :hours, :days, :weeks, :months, :years ]
        str = numberFormat.format(value * factors[units.index(loadUnit)])
      end
      str
    end

  end

end

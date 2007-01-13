#
# TaskScenario.rb - TaskJuggler
#
# Copyright (c) 2006, 2007 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# $Id$
#

require 'ScenarioData'

class TaskScenario < ScenarioData

  attr_reader :isRunAway

  def initialize(task, scenarioIdx)
    super
  end

  def prepareScenario
    @depends = []
    @precedes = []
    @previous = []
    @followers = []

    @isRunAway = false

    # The following variables are only used during scheduling
    @lastSlot = nil
    # The 'done' variables count scheduled values in number of time slots.
    @doneDuration = 0
    @doneLength = 0
    @doneEffort = 0
  end

  def Xref
    @property['depends', @scenarioIdx].each do |dependency|
      depTask = dependency.resolve(@project)
      if depTask.nil?
        raise "Task #{@property.id} has unknown depends #{task}"
      end

      @depends.push(depTask)
      @previous.push(depTask)
      depTask.addFollower(@scenarioIdx, @property)
    end

    @property['precedes', @scenarioIdx].each do |dependency|
      predTask = dependency.resolve(@project)
      if predTask.nil?
        raise "Task #{@property.id} has unknown precedes #{task}"
      end

      @precedes.push(predTask)
      @followers.push(predTask)
      predTask.addPrevious(@scenarioIdx, @property)
    end
  end

  def implicitXref
    # Automatically detect and mark task that have no duration criteria but
    # either proper start or end specification.
    return if !@property.leaf? || a('milestone')

    hasDurationSpec = a('length') != 0 || a('duration') != 0 || a('effort') != 0
    hasStartSpec = !(a('start').nil? && a('depends').empty?)
    hasEndSpec = !(a('end').nil? && a('precedes').empty?)

    @property['milestone', @scenarioIdx] =
      !hasDurationSpec && (hasStartSpec ^ hasEndSpec)
  end

  def preScheduleCheck
  end

  def postScheduleCheck
    @errors = 0
    @property.children.each do |task|
      @errors += 1 unless task.postScheduleCheck(@scenarioIdx)
    end

    # There is no point the check the parent if the child(s) have errors.
    return false if @errors > 0

    # Same for runaway tasks. They have already been reported.
    return false if isRunAway

    # Make sure the task is marked complete
    unless a('scheduled')
      error("Task #{@property.id} has not been marked as scheduled.")
    end

    # If the task has a follower or predecessor that is a runaway this task
    # is also incomplete.
    @followers.each do |follower|
      return false if follower.isRunAway(@scenarioIdx)
    end
    @previous.each do |previous|
      return false if previous.isRunAway(@scenarioIdx)
    end

    # Check if the start time is ok
    error("Task #{@property.id} has undefined start time") if a('start').nil?
    if a('start') < @project['start'] || a('start') > @project['end']
      error("The start time (#{a('start')}) of task #{@property.id} " +
            "is outside the project interval (#{@project['start']} - " +
            "#{@project['end']})")
    end
    if !a('minstart').nil? && a('start') < a('minstart')
      error("The start time (#{a('start')}) of task #{@property.id} " +
            "is too early. Must be after #{a('minstart')}.")
    end
    if !a('maxstart').nil? && a('start') > a('maxstart')
      error("The start time (#{a('start')}) of task #{@property.id} " +
            "is too late. Must be before #{a('maxstart')}.")
    end

    # Check if the end time is ok
    error("Task #{@property.id} has undefined end time") if a('end').nil?
    if a('end') < @project['start'] || a('end') > @project['end']
      error("The end time (#{a('end')}) of task #{@property.id} " +
            "is outside the project interval (#{@project['start']} - " +
            "#{@project['end']})")
    end
    if !a('minend').nil? && a('end') < a('minend')
      error("The end time (#{a('end')}) of task #{@property.id} " +
            "is too early. Must be after #{a('minend')}.")
    end
    if !a('maxend').nil? && a('end') > a('maxend')
      error("The end time (#{a('end')}) of task #{@property.id} " +
            "is too late. Must be before #{a('maxend')}.")
    end

    # Check that tasks fits into parent task.
    unless @property.parent.nil?
      parent = @property.parent
      if a('start') < parent['start', @scenarioIdx]
        error("The start date (#{a('start')}) of task #{@property.id} " +
              "is before the start date of the enclosing task " +
              "#{parent['start', scenarioIdx]}. ")
      end
      if a('end') > parent['end', @scenarioIdx]
        error("The end date (#{a('end')}) of task #{@property.id} " +
              "is after the end date of the enclosing task " +
              "#{parent['end', scenarioIdx]}. ")
      end
    end

    # Check that all preceding tasks end before this task.
    @previous.each do |task|
      if task['end', @scenarioIdx] > a('start')
        error("Task #{@property.id} starts before task #{@task.id} " +
              "ends needs to follow it.")
      end
    end

    # Check that all following tasks end before this task
    @followers.each do |task|
      if task['start', @scenarioIdx] < a('end')
        error("Task #{@property.id} ends after task #{@task.id} " +
              "starts but needs to precede it.")
      end
    end

    @errors == 0
  end

  def addFollower(task)
    @followers.push(task)
  end

  def addPrevious(task)
    @previous.push(task)
  end

  def nextSlot(slotDuration)
    return nil if a('scheduled')

    if a('forward')
      @lastSlot.nil? ? a('start') : @lastSlot + slotDuration
    else
      @lastSlot.nil? ? a('end') - slotDuration : @lastSlot - slotDuration
    end
  end

  def readyForScheduling?
    return false if a('scheduled')

    if a('forward')
      if !a('start').nil? &&
         (a('effort') != 0 || a('length') != 0 || a('duration') != 0 ||
          a('milestone')) &&
         a('end').nil?
        return true
      end
    else
      if !a('end').nil? &&
         (a('effort') != 0 || a('length') != 0 || a('duration') != 0 ||
          a('milestone')) &&
         a('start').nil?
        return true
      end
    end

    false
  end

  def schedule(slot, slotDuration)
    if a('forward')
       if @lastSlot.nil?
         @lastSlot = a('start') - slotDuration
         @tentativeEnd = slot + slotDuration
       end

       return false unless slot == @lastSlot + slotDuration

       @lastSlot = slot + slotDuration
    else
      if @lastSlot.nil?
        @lastSlot = a('end')
        @tentativeStart = slot
      end

      return false unless slot == @lastSlot - slotDuration

      @lastSlot = slot
    end

    if a('length') > 0 || a('duration') > 0
      @doneDuration += 1

      if @project.isWorkingTime(slot, slot + slotDuration)
        @doneLength += 1
      end

      if (a('length') > 0 && @doneLength >= a('length')) ||
         (a('duration') > 0 && @doneDuration >= a('duration'))
        if a('forward')
          @property['end', @scenarioIdx] = slot + slotDuration
          propagateEnd
        else
          @property['start', @scenarioIdx] = slot
          propagateStart
        end
        @property['scheduled', @scenarioIdx] = true
        return true
      end
    elsif a('effort') > 0
      bookResources(@scenarioIdx, slot, slotDuration)
      if @doneEffort >= a('effort')
        if a('forward')
          @property['end', @scenarioIdx] = @tentativeEnd
          propagateEnd
        else
          @property['start', @scenarioIdx] = @tentativeStart
          propagateStart
        end
        @property['scheduled', @scenarioIdx] = true
        return true
      end
    elsif a('milestone')
      puts "Setting milestone #{@property.id}"
      if a('forward')
        @property['end', @scenarioIdx] = a('start')
        propagateEnd
      else
        @property['start', @scenarioIdx] = a('end')
        propagateStart
      end
    else
      #TODO: Handle start/end task
    end
  end

  def propagateStart(notUpwards = true)
    return if a('start').nil?

    if a('milestone')
      @property['scheduled', @scenarioIdx] = true
      if a('end').nil?
        @property['end', @scenarioIdx] = a('start')
        propagateEnd(notUpwards)
      end
    end

    @previous.each do |task|
      if task['end', @scenarioIdx].nil? &&
         !task.latestEnd(@scenarioIdx).nil? &&
         !task['scheduled', @scenarioIdx] &&
         (!task['forward', @scenarioIdx] ||
          (task['effort', @scenarioIdx] == 0 &&
           task['length', @scenarioIdx] == 0 &&
           task['duration', @scenarioIdx] == 0 &&
           !task['milestone', @scenarioIdx]))
        task['end', @scenarioIdx] = task.latestEnd(@scenarioIdx)
        task.propagateEnd(@scenarioIdx, notUpwards)
      end
    end

    @property.children.each do |task|
      if !task.hasStartDependency(@scenarioIdx) &&
         !task['scheduled', @scenarioIdx]
        task['start', @scenarioIdx] = start
        task.propagateStart(@scenarioIdx, true)
      end
    end

    if notUpwards && !@property.parent.nil?
      @property.parent.scheduleContainer(@scenarioIdx, true)
    end
  end

  def propagateEnd(notUpwards = true)
    return if a('end').nil?

    if a('milestone')
      @property['scheduled', @scenarioIdx] = true
      if a('start').nil?
        @property['start', @scenarioIdx] = a('end')
        propagateStart(notUpwards)
      end
    end

    @followers.each do |task|
      if task['start', @scenarioIdx].nil? &&
         !task.earliestStart(@scenarioIdx).nil?
         !task['scheduled', @scenarioIdx] &&
         (task['forward', @scenarioIdx] ||
          (task['effort', @scenarioIdx] == 0 &&
           task['length', @scenarioIdx] == 0 &&
           task['duration', @scenarioIdx] == 0 &&
           !task['milestone', @scenarioIdx]))
        task['start', @scenarioIdx] = task.earliestStart(@scenarioIdx)
        task.propagateStart(@scenarioIdx, notUpwards)
      end
    end

    @property.children.each do |task|
      if !task.hasEndDependency(@scenarioIdx) &&
         !task['scheduled', @scenarioIdx]
        task['end', @scenarioIdx] = a('end')
        task.propagateEnd(@scenarioIdx, true)
      end
    end

    if notUpwards && !@property.parent.nil?
      @property.parent.scheduleContainer(@scenarioIdx, true)
    end
  end

  def scheduleContainer(notUpwards)
    return true if a('scheduled') || !@property.container?

    nStart = nil
    nEnd = nil

    @property.children.each do |task|
      return true if task['start', @scenarioIdx].nil? ||
                     task['end', @scenarioIdx].nil?
      if nStart.nil? || task['start', @scenarioIdx] < nStart
        nStart = task['start', @scenarioIdx]
      end
      if nEnd.nil? || task['end', @scenarioIdx] > nEnd
        nEnd = task['end', @scenarioIdx]
      end
    end

    if a('start').nil? || a('start') > nStart
      @property['start', @scenarioIdx] = nStart;
      propagateStart(notUpwards)
    end

    if a('end').nil? || a('end') < nEnd
      @property['end', @scenarioIdx] = nEnd
      propagateEnd(notUpwards)
    end

    @property['scheduled', @scenarioIdx] = true

    false
  end

  def hasStartDependency
    return true if @property.provided('start', @scenarioIdx) || @depends.empty?

    p = @property
    while (p = p.parent) do
      return true if p.provided('start', @scenarioIdx)
    end

    false
  end

  def hasEndDependency
    return true if @property.provided('end', @scenarioIdx) || @precedes.empty?

    p = @property
    while (p = p.parent) do
      return true if p.provided('end', @scenarioIdx)
    end

    false
  end

  def earliestStart
    startDate = TjTime.new(0)
    @previous.each do |task|
      if task['end', @scenarioIdx].nil?
        return nil if task['forward', @scenarioIdx]
      elsif task['end', @scenarioIdx] > startDate
        startDate = task['end', @scenarioIdx]
      end
    end

    a('depends').each do |dependency|
      potentialStartDate = dependency.task['end', @scenarioIdx]
      dateAfterLengthGap = potentialStartDate
      gapLength = dependency.gapLength
      while gapLength > 0 && dateAfterLengthGap < @project['end'] do
        if @project.isWorkingTime(dateAfterLengthGap)
          gapLength -= @project.scheduleGranularity
        end
        dateAfterLengthGap += @project.scheduleGranularity
      end

      if dateAfterLengthGap > potentialStartDate + dependency.gapDuration
        potentialStartDate = dateAfterLengthGap
      else
        potentialStartDate += dependency.gapDuration
      end

      startDate = potentialStartDate if potentialStartDate > startDate
    end

    # If any of the parent tasks has an explicit start date, the task must
    # start at or after this date.
    task = @property
    while (task = task.parent) do
      if task['start', @scenarioIdx] && task['start', @scenarioIdx] > startDate
        return task['start', @scenarioIdx]
      end
    end

    return startDate
  end

  def latestEnd
    endDate = TjTime.at(0)
    @followers.each do |task|
      if task['start', @scenarioIdx].nil?
        return nil unless task['forward', @scenarioIdx]
      elsif endDate == TjTime.at(0) ||
            task['start', @scenarioIdx] < endDate
	      endDate = task['start', @scenarioIdx]
      end
    end

    a('precedes').each do |dependency|
      potentialEndDate = dependency.task['start', @scenarioIdx]
      dateBeforeLengthGap = potentialEndDate
      gapLength = dependency.gapLength
      while gapLength > 0 && dateBeforeLengthGap < @project['start'] do
        if @project.isWorkingTime(dateBeforeLengthGap)
          gapLength -= @project.scheduleGranularity
        end
        dateBeforeLengthGap -= @project.scheduleGranularity
      end
      if dateBeforeLengthGap < potentialEndDate - dependency.gapDuration
        potentialEndDate = dateBeforeLengthGap
      else
        potentialEndDate -= dependency.gapDuration
      end

      endDate = potentialEndDate if potentialEndDate < endDate
    end

    task = @property
    while (task = task.parent) do
      if task['end', @scenarioIdx] && task['end', @scenarioIdx] < endDate
        return task['end', @scenarioIdx]
      end
    end
  end

  def bookResources(sc, date, slotDuration)
    iv = Interval.new(date, date + slotDuration)
    sbIdx = @project.dateToIdx(date)

    # We first have to make sure that if there are mandatory resources
    # that these are all available for the time slot.
    @property['allocate', sc].each do |allocation|
      if allocation.mandatory
        return unless allocation.onShift?(iv)

        # For mandatory allocations with alternatives at least one of the
        # alternatives must be available.
        found = false
        allocation.candidates.each do |candidate|
          # When a resource group is marked mandatory, all members of the
          # group must be available.
          allAvailable = true
          candidate.all.each do |resource|
            if !resource.available?(@scenarioIdx, sbIdx)
              allAvailable = false
              break
            end
          end
          if allAvailable
            found = true
            break
          end
        end

        return unless found
      end
    end

    @property['allocate', sc].each do |allocation|
      # TODO: Handle shifts
      # TODO: Handle limits

      # For persistent resources we capture the time slot where we
      # could not allocate it first. This is used during debug mode to
      # report contention intervals.
      if allocation.persistent && !allocation.lockedResource.nil
        if !bookResource(allocation.lockedResource, iv)
          # The resource could not be allocated.
          if allocation.lockedResource.booked?(sbIdx) &&
            allocation.conflictStart.nil?
            # Store starting time slot
            allocation.conflictStart = date
          end
        elsif !allocation.conflictStart.nil
          # Reset starting time slot
          allocation.conflictStart = nil
        end
      else
        found = false
        busy = false
        # Create a list of candidates in the proper order and assign
        # the first one available.
        createCandidateList(sbIdx, allocation).each do |candidate|
          if bookResource(candidate, sbIdx)
            allocation.lockedResource = candidate
            found = true
            break
          elsif candidate.booked?
            busy = true
          end
        end
        # Set of reset the conflict start time slot.
        if found
          allocation.conflictStart = nil
        elsif busy && allocation.conflictStart.nil?
          allocation.conflictStart = date
        end
      end
    end
  end

  def bookResource(resource, sbIdx)
    resource.all.each do |r|
      if r.book(@scenarioIdx, sbIdx, @property)

        if a('bookedresources').empty?
	        if a('forward')
            @property['start', @scenarioIdx] = @project.idxToDate(sbIdx)
          else
            @property['end', @scenarioIdx] = @project.idxToDate(sbIdx + 1)
          end
        end

        @tentativeStart = @project.idxToDate(sbIdx)
        @tentativeEnd = @project.idxToDate(sbIdx + 1)

        @doneEffort += 1

        a('bookedresources') << r unless a('bookedresources').index(r)
      end
    end
  end

  def createCandidateList(sbIdx, allocation)
    allocation.candidates
  end

  def markAsRunaway
    puts "Task #{@property.get('id')} does not fit into project time frame"
    @isRunAway = true
  end
end

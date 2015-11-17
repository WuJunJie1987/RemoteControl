#!/usr/bin/env ruby

require 'daemons'
require 'drb/drb'

class DrbServer
  def initialize
    @patients={}
  end

  def isPatientOnline?(p)
    return !(@patients[p].nil? or @patients[p][:obj].nil?)
  end

  def sendToPatient(p, msg)
    if @patients[p].nil? or @patients[p][:obj].nil?
      return false
    end
    @patients[p][:obj].sendMsg msg
    return true
  end

  def patientOnline(p, obj)
    @patients[p]||={}
    @patients[p][:obj]=obj
  end

  def patientOffline(p)
    @patients[p]||={}
    @patients[p][:obj]=nil
  end

  def recvFromPatient(p, msg)
    @patients[p]||={}
    @patients[p][:time]=Time.now
    @patients[p][:msg]=msg
  end

  def getPatientLastMsg(p)
    return nil if @patients[p].nil?
    return {time: @patients[p][:time], msg: @patients[p][:msg]}
  end
end

Daemons.run_proc 'drbServer.rb' do
  serverObj=DrbServer.new
  $SAFE=1
  DRb.start_service 'druby://localhost:8099', serverObj
  DRb.thread.join
end


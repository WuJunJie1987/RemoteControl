require 'drb/drb'

DOC_TIMEOUT=600
PAT_TIMEOUT=600

SERVER_URI="druby://localhost:8099"

class Patient
  include DRb::DRbUndumped

  def initialize
    @received=false
    @msg=nil
  end
  
  def sendMsg(msg)
    @received=true
    @msg=msg
  end

  def received?
    return @received
  end

  def getMsg
    msg=@msg
    @msg=nil
    @received=false
    return msg
  end
end

class Log < ActiveRecord::Base
end

class RishenaController < ApplicationController
  
  def doctor
    id=params[:id]
    if id.nil?
      render plain: "Error: Require patient id"
      return
    end

    opt=params[:opt]
    if opt.nil?
      render plain: "Error: Require option"
      return
    end

    DRb.start_service
    serverObj=DRbObject.new_with_uri SERVER_URI
    if serverObj.nil?
      render plain: "Error: Can't acquire Drb Server Object"
      return
    end

    timeout=true
    DOC_TIMEOUT.times do
      if serverObj.isPatientOnline? id
        timeout=false
        break
      else
        sleep 1
      end
    end

    if timeout
      render plain: 'Timeout: unconnected'
      return
    end

    if opt=='connect'
      render plain: 'Success: connected'
    elsif opt=='send'
      msg=request.body.read
      if msg.nil? or msg.strip==''
        render plain: 'Error: empty message'
        return
      end
      
      sendTime=Time.now
      serverObj.sendToPatient id, msg
      
      timeout=false
      DOC_TIMEOUT.times do
        ret=serverObj.getPatientLastMsg id
        if ret.nil? or ret[:time].nil? or ret[:time]<sendTime
          sleep 1
        else
          render plain: "Success: #{ret[:time].strftime '%F %T'}\n#{ret[:msg]}"
          timeout=false
          break
        end
      end
      if timeout
        render plain: "Timeout: no response"
      end
    else
      render plain: "Error: Unknown option"
    end
  end

  def patient
    id=params[:id]
    if id.nil?
      render plain: "Error: Require patient id"
      return
    end

    opt=params[:opt]
    if opt.nil?
      render plain: "Error: Require option"
      return
    end

    DRb.start_service
    serverObj=DRbObject.new_with_uri SERVER_URI
    if serverObj.nil?
      render plain: "Error: Can't acquire Drb Server Object"
      return
    end

    object=Patient.new
    serverObj.patientOnline id, object

    msg=request.body.read
    msg=nil if msg.nil? or msg.strip==''

    if opt=='close'
      msg='closed' if msg.nil?
      serverObj.recvFromPatient id, msg
      render plain: 'Success: closed'
    elsif opt=='keep-alive'
      serverObj.recvFromPatient id, msg unless msg.nil?
      timeout=true
      PAT_TIMEOUT.times do
        if object.received?
          timeout=false
          render plain: "Success: #{object.getMsg}"
          break
        else
          sleep 1
        end
      end

      if timeout
        render plain: "Timeout: keep-alive"
      end
    end
    serverObj.patientOffline id
  end

  def newLog
    id=params[:id]
    if id.nil?
      render plain: 'Error: require id'
      return
    end

    len=request.headers['log-length'].to_i
    if len<=0
      render plain: 'Error: illegal log-length'
      return
    end

    bs=request.body.read
    count=0
    bs.each_byte.each_slice len do |s|
      if s.size==len
        Log.create dev_id: id, time: Time.now, log: s.pack('C*')
        count+=1
      else
        render plain: 'Failed'
      end
    end

    render plain: "Success: #{count} logs received"
  end

  def getLog
    id=params[:id]
    if id.nil?
      render plain: 'Error: require id'
      return
    end

    count=params[:count].to_i
    start=params[:start].to_i

    logs=Log.where dev_id: id
    logs=logs.drop start
    logs=logs.first count if count>0

    ba=[]
    logs.each do |log|
      ba<<log.log
    end
    if ba.size>0
      render plain: ba.join
    else
      render plain: 'No log'
    end
  end

  def deleteLog
    id=params[:id]
    if id.nil?
      render plain: 'Error: require id'
      return
    end

    count=params[:count].to_i
    start=params[:start].to_i

    logs=Log.where dev_id: id
    logs=logs.drop start
    logs=logs.first count if count>0

    logs.each do |log|
      log.destroy
    end
    
    render plain: "Success: #{logs.size} deleted"
  end
end

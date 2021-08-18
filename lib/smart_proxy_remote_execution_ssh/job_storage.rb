# lib/job_storage.rb

module Proxy::RemoteExecution::Ssh
  class JobStorage
    def initialize
      @db = Sequel.sqlite
      @db.create_table :jobs do
        DateTime :timestamp, null: false, default: Sequel::CURRENT_TIMESTAMP
        String :uuid, fixed: true, size: 36, primary_key: true, null: false
        String :hostname, null: false, index: true
        String :execution_plan_uuid, fixed: true, size: 36, null: false, index: true
        Integer :run_step_id, null: false
        String :job, text: true
      end
    end

    def find_job(uuid)
      jobs.where(uuid: uuid).first
    end

    def job_uuids_for_host(hostname)
      jobs_for_host(hostname).order(:timestamp)
                             .select_map(:uuid)
    end

    def store_job(hostname, execution_plan_uuid, run_step_id, job, uuid: SecureRandom.uuid, timestamp: Time.now.utc)
      jobs.insert(timestamp: timestamp,
                  uuid: uuid,
                  hostname: hostname,
                  execution_plan_uuid: execution_plan_uuid,
                  run_step_id: run_step_id,
                  job: job)
      uuid
    end

    def drop_job(execution_plan_uuid, run_step_id)
      jobs.where(execution_plan_uuid: execution_plan_id, run_step_id: run_step_id).delete
    end

    private

    def jobs_for_host(hostname)
      jobs.where(hostname: hostname)
    end

    def jobs
      @db[:jobs]
    end
  end
end

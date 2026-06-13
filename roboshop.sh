script_name=$(basename $0 .sh)
script_dir=$(realpath $(dirname $0))
logs_dir="${script_dir}/logs"
timestamp=$(date +"%Y%m%d_%H%M%S")
log_file="${logs_dir}/${script_name}_${timestamp}.log"
mkdir -p $logs_dir

export AWS_PROFILE="deva"
export ANSIBLE_FORCE_COLOR=True
export PYTHONUNBUFFERED=1

exec > >(tee -a $log_file) 2>&1

#color variables
R="\e[31m"
Y="\e[32m"
G="\e[33m"
B="\e[34m"
N="\e[0m"

#timing
start_time=$(date +%s)
echo -e "Script run started @ $B ... $(date) ... $N"

function calculate_total_time(){
    end_time=$(date +%s)
    time_taken=$(( $end_time - $start_time ))
    seconds=$(( time_taken % 60 ))
    minutes=$(( time_taken/60 % 60 ))
    hours=$(( time_taken/60/60 ))

    echo -e "Script run ended @ $B ... $(date) ... $N"
    echo "===========Total Time Taken================"
    echo -e "---------($B ${hours} hrs, ${minutes} min, ${seconds} sec $N)-----------"
    echo "==========================================="
}

export ANSIBLE_CONFIG="${script_dir}/ansible.cfg"

instances=("mongodb" "redis" "rabbitmq" "mysql" "catalogue" "cart" "user" "shipping" "payment" "dispatch" "frontend")
dbs=("mongodb" "redis" "rabbitmq" "mysql")
backends=("catalogue" "cart" "user" "shipping" "payment" "dispatch")
frontends=("frontend")

json_payload=$(jq -n \
    --argjson instances "$(printf '%s\n' "${instances[@]}" | jq -R . | jq -s .)" \
    '{
        instance_action: "create",
        instances: $instances
    }'
)

ansible-playbook "${script_dir}/create_terminate_instances.yaml" \
    -e "$json_payload"


function validate_playbook(){
    status=$1
    component=$2
    if [[ $status -ne 0 ]]; then
        echo -e "$R Something is up, There is an error in running the role for the instance ... $1 ... $N"
        calculate_total_time
        exit 1;
    else
        echo -e "$G completed the role for the instance ... $component .... $N"
    fi
}

validate_playbook $? "main-playbook-creating instances"

db_pids=()
db_names=()
for instance in "${dbs[@]}"; do
    echo -e "$B running the role for DB instance ... $instance (parallel) .... $N"
    ansible-playbook "${script_dir}/roboshop.yaml" -e component="$instance" &
    db_pids+=("$!")
    db_names+=("$instance")
done

for i in "${!db_pids[@]}"; do
    wait "${db_pids[$i]}"
    validate_playbook $? "${db_names[$i]}"
    echo "==========================================================="
done

backend_pids=()
backend_names=()
for instance in "${backends[@]}"; do
    echo -e "$B running the role for backend instance ... $instance (parallel) .... $N"
    ansible-playbook "${script_dir}/roboshop.yaml" -e component="$instance" &
    backend_pids+=("$!")
    backend_names+=("$instance")
done

for i in "${!backend_pids[@]}"; do
    wait "${backend_pids[$i]}"
    validate_playbook $? "${backend_names[$i]}"
    echo "==========================================================="
done

for instance in "${frontends[@]}"; do
    echo -e "$B running the role for frontend instance ... $instance .... $N"
    ansible-playbook "${script_dir}/roboshop.yaml" -e component="$instance"
    validate_playbook $? "$instance"
    echo "==========================================================="
done

calculate_total_time
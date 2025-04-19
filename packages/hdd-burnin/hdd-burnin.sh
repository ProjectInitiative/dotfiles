#!/usr/bin/env bash

# HDD Burn-In Test Script
# =======================
#
# WARNING: This script performs DESTRUCTIVE testing using 'badblocks -w'.
# ALL DATA ON SELECTED DRIVES WILL BE PERMANENTLY ERASED.
# Proceed with extreme caution and ensure you have selected the correct drives.
#
# Requirements: smartmontools (smartctl), e2fsprogs (badblocks), lsblk, jq
# Run as root or using sudo.

# --- Configuration ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_BASE_DIR="hdd_burn_in_reports"
MAIN_REPORT_DIR="${REPORT_BASE_DIR}/${TIMESTAMP}"
SMART_START_DELAY=15 # Seconds delay before starting SMART test per drive

# --- Functions ---

# Function to log messages to both console and a main log file
log_message() {
    local message="$1"
    # Ensure main report directory exists before logging to main file
    mkdir -p "${MAIN_REPORT_DIR}"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] ${message}" | tee -a "${MAIN_REPORT_DIR}/main_script.log"
}

# Function to log messages specific to a drive
log_drive_message() {
    local drive_path="$1"
    local drive_id="$2"
    local message="$3"
    local drive_log_dir="${MAIN_REPORT_DIR}/${drive_id}"
    local drive_log_file="${drive_log_dir}/test_progress.log"
    # Create directory if it doesn't exist when logging first message for the drive
    mkdir -p "${drive_log_dir}"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] ${message}" | tee -a "${drive_log_file}"
}

# Function to run a command and log its output for a specific drive
run_drive_command() {
    local drive_path="$1"
    local drive_id="$2"
    local log_filename="$3"
    shift 3 # Remove the first three arguments (drive_path, drive_id, log_filename)
    local command_to_run=("$@") # Remaining arguments form the command
    local drive_log_dir="${MAIN_REPORT_DIR}/${drive_id}"
    local output_log="${drive_log_dir}/${log_filename}"

    # Ensure directory exists before running command
    mkdir -p "${drive_log_dir}"

    # Log command only if it's not a frequent poll
    if [[ "${log_filename}" != "smart_selftest_log_temp.log" ]]; then
        log_drive_message "$drive_path" "$drive_id" "Running command: ${command_to_run[*]}"
    fi

    # Execute the command using sudo, redirecting stdout and stderr to the log file
    sudo "${command_to_run[@]}" >> "${output_log}" 2>&1
    local exit_code=$?
    # Avoid logging excessive detail for frequent polls like smartctl -l selftest
    # Log exit code only if non-zero or for specific commands
    if [[ $exit_code -ne 0 || "${log_filename}" =~ ^(smart_health|smart_attributes|badblocks|smart_extended_test_start|smart_extended_test_abort) ]]; then
      # Log non-zero exit code for any command, or zero exit code for specific important ones
      if [[ $exit_code -ne 0 ]]; then
          log_drive_message "$drive_path" "$drive_id" "Command finished with non-zero exit code: ${exit_code}"
      elif [[ "${log_filename}" =~ ^(smart_health|smart_attributes|badblocks|smart_extended_test_start|smart_extended_test_abort) ]]; then
           log_drive_message "$drive_path" "$drive_id" "Command finished successfully (Exit Code: 0)." # Log success for key steps
      fi
    fi
    return $exit_code
}

# Function to perform tests on a single drive
test_drive() {
    local drive_path="$1"
    local drive_id="$2" # Use a unique identifier like serial or model-serial
    local drive_log_dir="${MAIN_REPORT_DIR}/${drive_id}"
    local summary_file="${drive_log_dir}/summary.txt"
    local errors_occurred=0

    # Initial log message will create the directory via log_drive_message
    log_drive_message "$drive_path" "$drive_id" "Starting tests for ${drive_path} (ID: ${drive_id}). Log Directory: ${drive_log_dir}"

    # Create summary file header
    echo "Burn-In Test Report for Drive: ${drive_path} (ID: ${drive_id})" > "${summary_file}"
    echo "Test Started: $(date)" >> "${summary_file}"
    echo "--------------------------------------------------" >> "${summary_file}"


    # 1. Initial S.M.A.R.T. Health Check
    log_drive_message "$drive_path" "$drive_id" "Running Initial S.M.A.R.T. Health Check..."
    run_drive_command "$drive_path" "$drive_id" "smart_health_initial.log" smartctl -H "$drive_path"
    health_exit_code=$?
    # Check exit code AND output for failure strings
    if [[ $health_exit_code -ne 0 ]] || grep -q -E 'FAILED!|UNKNOWN!|FAILURE!' "${drive_log_dir}/smart_health_initial.log"; then
        log_drive_message "$drive_path" "$drive_id" "ERROR: Initial S.M.A.R.T. health check failed or indicates problems (Exit Code: $health_exit_code)."
        echo "Initial S.M.A.R.T. Health: FAILED" >> "${summary_file}"
        errors_occurred=1
    else
        log_drive_message "$drive_path" "$drive_id" "Initial S.M.A.R.T. health check: PASSED."
        echo "Initial S.M.A.R.T. Health: PASSED" >> "${summary_file}"
    fi
    # Log full attributes regardless of health check result
    run_drive_command "$drive_path" "$drive_id" "smart_attributes_initial.log" smartctl -a "$drive_path"

    # 2. Extended S.M.A.R.T. Self-Test
    # Only attempt if initial health check passed
    if [[ $errors_occurred -eq 0 ]]; then
        log_drive_message "$drive_path" "$drive_id" "Waiting ${SMART_START_DELAY}s before starting Extended S.M.A.R.T. Self-Test..."
        sleep "$SMART_START_DELAY"
        log_drive_message "$drive_path" "$drive_id" "Attempting to start Extended S.M.A.R.T. Self-Test..."
        run_drive_command "$drive_path" "$drive_id" "smart_extended_test_start.log" smartctl -t long "$drive_path"
        start_test_exit_code=$?
        start_test_output=$(cat "${drive_log_dir}/smart_extended_test_start.log")

        # --- Revised Logic to Handle Existing Tests ---
        # Proceed to monitoring if:
        # - Command succeeded (exit code 0)
        # - Exit code is 4 (often means test active/drive busy/refused)
        # - Output contains specific messages indicating test active/queued/refused
        # Added "Can't start self-test" to the grep pattern
        if [[ $start_test_exit_code -eq 0 || $start_test_exit_code -eq 4 || \
              $(echo "$start_test_output" | grep -q -Ei 'Self-test routine already active|Please wait|Can.t start self-test without aborting') ]]; then

            # Determine specific reason for logging message
            if [[ $start_test_exit_code -eq 4 || $(echo "$start_test_output" | grep -q -Ei 'Self-test routine already active|Can.t start self-test without aborting') ]]; then
                 log_drive_message "$drive_path" "$drive_id" "Warning: Extended S.M.A.R.T. self-test may have been already running or drive reported busy/refused (Exit Code: $start_test_exit_code). Will monitor."
            else # Exit code 0 and no specific message, or "Please wait"
                 log_drive_message "$drive_path" "$drive_id" "Extended S.M.A.R.T. self-test started/queued. Monitoring progress..."
            fi
            echo "Extended S.M.A.R.T. Test: MONITORING" >> "${summary_file}"
            # Proceed to monitoring loop (handled by monitoring_initiated flag later)

        else # Failed for other reasons (non-zero exit code other than 4)
            log_drive_message "$drive_path" "$drive_id" "ERROR: Failed to start extended S.M.A.R.T. self-test (Exit Code: $start_test_exit_code)."
            echo "Extended S.M.A.R.T. Test: START FAILED (Code ${start_test_exit_code})" >> "${summary_file}"
            errors_occurred=1 # Mark error for overall summary
        fi
        # --- End Revised Logic ---
    else
         log_drive_message "$drive_path" "$drive_id" "Skipping Extended S.M.A.R.T. Self-Test due to initial health check failure."
         echo "Extended S.M.A.R.T. Test: SKIPPED" >> "${summary_file}"
    fi

    # Proceed with monitoring only if monitoring was initiated
    local monitoring_initiated=0
    if grep -q "Extended S.M.A.R.T. Test: MONITORING" "${summary_file}"; then
        monitoring_initiated=1
    fi

    if [[ $monitoring_initiated -eq 1 ]]; then
        local test_running=1
        local poll_interval=600 # Check every 10 minutes (adjust as needed)
        local max_wait_hours=48 # Maximum wait time for the test (adjust as needed)
        local wait_start_time=$(date +%s)
        local consecutive_poll_errors=0
        local max_poll_errors=5 # Abort polling if status check fails too many times
        local last_poll_status_log="" # Track last logged status to reduce noise
        local unknown_status_count=0
        local max_unknown_status=3 # Fail if status is unknown too many times

        while [[ $test_running -eq 1 ]]; do
            # Add a small delay *before* polling to further stagger checks across drives
            sleep $((RANDOM % 10 + 1)) # Random 1-10 sec delay before poll

            # Create temp file locally first to capture output
            local temp_selftest_log="${drive_log_dir}/smart_selftest_log_temp.log"
            # Run smartctl directly with sudo to capture output
            sudo smartctl -l selftest "$drive_path" > "$temp_selftest_log" 2>&1
            local poll_exit_code=$?

            # Append raw poll output to the main selftest log
            cat "$temp_selftest_log" >> "${drive_log_dir}/smart_selftest_log.log"

            if [[ $poll_exit_code -ne 0 ]]; then
                 log_drive_message "$drive_path" "$drive_id" "Warning: Failed to poll S.M.A.R.T. self-test status (Exit Code: $poll_exit_code)."
                 consecutive_poll_errors=$((consecutive_poll_errors + 1))
                 if [[ $consecutive_poll_errors -ge $max_poll_errors ]]; then
                     log_drive_message "$drive_path" "$drive_id" "ERROR: Aborting S.M.A.R.T. test monitoring due to repeated polling failures."
                     local test_result_line="Extended S.M.A.R.T. Test Result: POLLING FAILED"
                     sed -i "s|^Extended S.M.A.R.T. Test: MONITORING.*|${test_result_line}|" "${summary_file}"
                     errors_occurred=1
                     test_running=0
                 fi
                 rm -f "$temp_selftest_log"
                 # Wait full interval before next attempt
                 sleep "$poll_interval"
                 continue
            else
                consecutive_poll_errors=0 # Reset error count on successful poll
            fi

            # --- Improved Parsing Logic ---
            # Find the line for test #1 (most recent)
            local test_line_1=$(grep '^# *1 ' "$temp_selftest_log")
            local test_status_parsed="Unknown" # Default status
            local test_progress="?"  # Default progress

            if [[ -n "$test_line_1" ]]; then
                # Check for various completion/failure states using keywords
                if echo "$test_line_1" | grep -q 'Completed without error'; then
                    test_status_parsed="Completed_passed"
                    test_progress="100"
                elif echo "$test_line_1" | grep -q 'Completed'; then # Handles completed with errors too
                    test_status_parsed="Completed_error"
                    test_progress="100"
                elif echo "$test_line_1" | grep -q 'Failed'; then
                    test_status_parsed="Failed"
                    test_progress="?"
                elif echo "$test_line_1" | grep -q 'Aborted'; then
                    test_status_parsed="Aborted"
                    test_progress="?"
                elif echo "$test_line_1" | grep -q 'Interrupted'; then
                    test_status_parsed="Interrupted"
                    test_progress="?"
                elif echo "$test_line_1" | grep -q -E 'In progress|Pending|progress'; then # Added 'progress' as keyword
                    test_status_parsed="In_progress"
                    # Extract percentage (e.g., "90%") - look for number followed by %
                    test_progress=$(echo "$test_line_1" | grep -o -E '[0-9]+%') || test_progress="?" # Keep ? if grep fails
                    test_progress=${test_progress%\%} # Remove % sign
                else
                    # Some other status or format not recognized
                    test_status_parsed="Unknown_Format"
                fi
            else
                # Line for test #1 not found in output
                test_status_parsed="Polling_Format_Error"
                log_drive_message "$drive_path" "$drive_id" "Warning: Could not find line for test #1 in smartctl output."
            fi
            # --- End Improved Parsing Logic ---


            # Log polling status only if it changed
            local current_poll_status_log="Status: ${test_status_parsed} (${test_progress}%)"
            if [[ "$current_poll_status_log" != "$last_poll_status_log" ]]; then
              log_drive_message "$drive_path" "$drive_id" "Polling S.M.A.R.T.: ${current_poll_status_log}"
              last_poll_status_log="$current_poll_status_log"
            fi

            # Handle state changes based on parsed status
            local test_result_line="" # Used to update summary file

            if [[ "$test_status_parsed" == "Completed_passed" ]]; then
                log_drive_message "$drive_path" "$drive_id" "Extended S.M.A.R.T. self-test result: PASSED."
                test_result_line="Extended S.M.A.R.T. Test Result: PASSED"
                test_running=0
            elif [[ "$test_status_parsed" == "Completed_error" ]]; then
                log_drive_message "$drive_path" "$drive_id" "ERROR: Extended S.M.A.R.T. self-test completed with errors. Full line: $test_line_1"
                test_result_line="Extended S.M.A.R.T. Test Result: FAILED (Completed with error)"
                errors_occurred=1
                test_running=0
            elif [[ "$test_status_parsed" == "Failed" || "$test_status_parsed" == "Aborted" || "$test_status_parsed" == "Interrupted" ]]; then
                log_drive_message "$drive_path" "$drive_id" "ERROR: Extended S.M.A.R.T. self-test ended with status: $test_status_parsed. Full line: $test_line_1"
                test_result_line="Extended S.M.A.R.T. Test Result: ${test_status_parsed^^}" # Uppercase status
                errors_occurred=1
                test_running=0
            elif [[ "$test_status_parsed" == "In_progress" ]]; then
                 unknown_status_count=0 # Reset unknown count if progress is normal
                 # Timeout check
                 local current_time=$(date +%s)
                 local elapsed_seconds=$((current_time - wait_start_time))
                 local max_wait_seconds=$((max_wait_hours * 3600))
                 if [[ $elapsed_seconds -gt $max_wait_seconds ]]; then
                     log_drive_message "$drive_path" "$drive_id" "ERROR: Extended S.M.A.R.T. self-test timed out after ${max_wait_hours} hours."
                     test_result_line="Extended S.M.A.R.T. Test Result: TIMEOUT"
                     errors_occurred=1
                     test_running=0
                     # Attempt to abort the test
                     log_drive_message "$drive_path" "$drive_id" "Attempting to abort timed-out S.M.A.R.T. test..."
                     run_drive_command "$drive_path" "$drive_id" "smart_extended_test_abort.log" smartctl -X "$drive_path"
                 fi
            else # Handles Unknown_Format, Polling_Format_Error, Unknown etc.
                 log_drive_message "$drive_path" "$drive_id" "Warning: Unexpected or unparsed S.M.A.R.T. self-test status: '$test_status_parsed'. Full line: '$test_line_1'. Continuing poll."
                 unknown_status_count=$((unknown_status_count + 1))
                 if [[ $unknown_status_count -ge $max_unknown_status ]]; then
                     log_drive_message "$drive_path" "$drive_id" "ERROR: Aborting S.M.A.R.T. test monitoring due to repeated unknown status."
                     test_result_line="Extended S.M.A.R.T. Test Result: UNKNOWN STATUS"
                     errors_occurred=1
                     test_running=0
                 fi
            fi

            # Update summary file if test finished
            if [[ $test_running -eq 0 && -n "$test_result_line" ]]; then
                 sed -i "s|^Extended S.M.A.R.T. Test: MONITORING.*|${test_result_line}|" "${summary_file}"
            fi

            rm -f "$temp_selftest_log" # Clean up temp file

            # Wait for the remainder of the poll interval if the test is still running
            if [[ $test_running -eq 1 ]]; then
                sleep "$poll_interval"
            fi
        done # End while test_running
    fi # End of monitoring block

    # 3. Destructive Read/Write Test (badblocks)
    # Only run if SMART test didn't explicitly fail (or was skipped without initial failure)
    local run_badblocks=0
    if [[ $errors_occurred -eq 0 ]]; then
        run_badblocks=1
    elif grep -q "Extended S.M.A.R.T. Test: SKIPPED" "${summary_file}"; then
        # Only run badblocks if SMART was skipped due to initial health PASS
        if grep -q "Initial S.M.A.R.T. Health: PASSED" "${summary_file}"; then
             # This case should not happen based on current logic, but check anyway
             log_drive_message "$drive_path" "$drive_id" "Warning: SMART skipped despite initial pass? Proceeding with badblocks."
             run_badblocks=1
        fi
    fi


    if [[ $run_badblocks -eq 1 ]]; then
        log_drive_message "$drive_path" "$drive_id" "Starting DESTRUCTIVE Read/Write Test (badblocks -wsvb 4096)... THIS WILL TAKE A LONG TIME."
        # Ensure previous line exists before trying to replace it, otherwise append
        if ! grep -q "Badblocks Test:" "${summary_file}"; then
            echo "Badblocks Test: STARTED" >> "${summary_file}"
        else
             sed -i "s|^Badblocks Test:.*|Badblocks Test: STARTED|" "${summary_file}"
        fi

        local badblocks_output_file="${drive_log_dir}/badblocks_list.txt"
        local badblocks_log_file="${drive_log_dir}/badblocks_run.log"
        # Run badblocks: -w (write-mode), -s (progress), -v (verbose), -b 4096 (blocksize), -o (output bad blocks list)
        run_drive_command "$drive_path" "$drive_id" "badblocks_run.log" badblocks -wsvb 4096 -o "${badblocks_output_file}" "${drive_path}"
        local badblocks_exit_code=$?

        local badblocks_passed=0 # Flag to track if badblocks passed
        local badblocks_result_line="Badblocks Test Result:"

        if [[ $badblocks_exit_code -ne 0 ]]; then
            log_drive_message "$drive_path" "$drive_id" "Warning: badblocks command finished with non-zero exit code ${badblocks_exit_code}. Checking for bad blocks found..."
        fi

        # Check if the badblocks list file exists and is non-empty
        if [[ -f "${badblocks_output_file}" && -s "${badblocks_output_file}" ]]; then
            local bad_block_count=$(wc -l < "${badblocks_output_file}")
            log_drive_message "$drive_path" "$drive_id" "ERROR: badblocks found ${bad_block_count} bad block(s). See ${badblocks_output_file}."
            badblocks_result_line+=" FAILED (${bad_block_count} bad blocks found)"
            errors_occurred=1
        else
            # If the list file is empty or absent, check the exit code for other errors
            if [[ $badblocks_exit_code -eq 0 ]]; then
                log_drive_message "$drive_path" "$drive_id" "badblocks test completed successfully with 0 bad blocks found."
                badblocks_result_line+=" PASSED (0 bad blocks)"
                badblocks_passed=1
                # Optionally remove the empty badblocks list file if it exists
                rm -f "${badblocks_output_file}"
            else
                # Exit code was non-zero, but no bad blocks were listed. Indicates another error (like the 32-bit limit previously, or permissions, etc.)
                log_drive_message "$drive_path" "$drive_id" "ERROR: badblocks exited non-zero (${badblocks_exit_code}) but no bad blocks were listed. Check ${badblocks_log_file} for errors (e.g., permissions, device access, value too large)."
                badblocks_result_line+=" FAILED (Command Error - Exit ${badblocks_exit_code})"
                errors_occurred=1
            fi
        fi
        # Update summary file for badblocks test
        sed -i "s|^Badblocks Test:.*|${badblocks_result_line}|" "${summary_file}"
    else
         log_drive_message "$drive_path" "$drive_id" "Skipping Destructive Read/Write Test due to prior S.M.A.R.T. test failure or initial health failure."
         echo "Badblocks Test: SKIPPED" >> "${summary_file}"
    fi


    # 4. Final S.M.A.R.T. Check
    log_drive_message "$drive_path" "$drive_id" "Running Final S.M.A.R.T. Check..."
    run_drive_command "$drive_path" "$drive_id" "smart_health_final.log" smartctl -H "$drive_path"
    health_exit_code=$?
    # Log final attributes regardless
    run_drive_command "$drive_path" "$drive_id" "smart_attributes_final.log" smartctl -a "$drive_path"

    # Determine final health status line
    local final_health_line="Final S.M.A.R.T. Health:"
    if [[ $health_exit_code -ne 0 ]] || grep -q -E 'FAILED!|UNKNOWN!|FAILURE!' "${drive_log_dir}/smart_health_final.log"; then
        log_drive_message "$drive_path" "$drive_id" "ERROR: Final S.M.A.R.T. health check failed or indicates problems (Exit Code: $health_exit_code)."
        final_health_line+=" FAILED"
        errors_occurred=1 # Ensure overall failure if final check fails
    else
        log_drive_message "$drive_path" "$drive_id" "Final S.M.A.R.T. health check: PASSED."
        final_health_line+=" PASSED"
    fi
    # Append or replace the final health line in the summary
     if ! grep -q "Final S.M.A.R.T. Health:" "${summary_file}"; then
        echo "$final_health_line" >> "${summary_file}"
    else
         sed -i "s|^Final S.M.A.R.T. Health:.*|${final_health_line}|" "${summary_file}"
    fi


    # 5. Final Summary
    echo "--------------------------------------------------" >> "${summary_file}"
    local overall_result_line="Overall Result:"
    if [[ $errors_occurred -eq 0 ]]; then
        log_drive_message "$drive_path" "$drive_id" "All tests PASSED for ${drive_path}."
        overall_result_line+=" PASSED"
    else
        log_drive_message "$drive_path" "$drive_id" "One or more tests FAILED or encountered errors for ${drive_path}."
        overall_result_line+=" FAILED"
    fi
     # Append or replace the overall result line in the summary
     if ! grep -q "Overall Result:" "${summary_file}"; then
        echo "$overall_result_line" >> "${summary_file}"
    else
         sed -i "s|^Overall Result:.*|${overall_result_line}|" "${summary_file}"
    fi

    echo "Test Finished: $(date)" >> "${summary_file}"
    log_drive_message "$drive_path" "$drive_id" "Testing finished for ${drive_path}."

    # Return 0 if PASSED, 1 if FAILED
    return $errors_occurred
}

# --- Main Script ---

# Check for root privileges early
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root (or using sudo) to access raw disk devices and run tools like smartctl/badblocks."
   exit 1
fi

# Create base reporting directory first (needed for early log messages)
mkdir -p "${MAIN_REPORT_DIR}"
log_message "Starting HDD Burn-In Script..."
log_message "Report directory: ${MAIN_REPORT_DIR}"

# Check for required commands
# Added jq check
# Check common locations for tools if `command -v` fails initially
found_all_commands=1
# Added cut, sed, tail, head, tr, wc, sleep, date, grep, awk, findmnt, find, lsblk, smartctl, badblocks, jq
for cmd in smartctl badblocks lsblk jq awk grep tee mkdir date sleep wc findmnt find sudo sed rm wc cut tail head tr; do
    if ! command -v $cmd &> /dev/null; then
        # Try common paths if not in default PATH
        found_in_path=0
        for path in /usr/sbin /sbin /usr/bin /bin /usr/local/bin /usr/local/sbin; do
            if [[ -x "${path}/${cmd}" ]]; then
                found_in_path=1
                break
            fi
        done
        if [[ $found_in_path -eq 0 ]]; then
            echo "Error: Required command '$cmd' not found in PATH or common locations. Please install it."
            # Provide specific install hints
            if [[ "$cmd" == "jq" ]]; then
                echo "Try: 'sudo apt update && sudo apt install jq' or 'sudo yum install jq' or 'sudo dnf install jq'"
            elif [[ "$cmd" == "smartctl" ]]; then
                 echo "Try: 'sudo apt update && sudo apt install smartmontools' or 'sudo yum install smartmontools' or 'sudo dnf install smartmontools'"
            elif [[ "$cmd" == "badblocks" ]]; then
                 echo "Try: 'sudo apt update && sudo apt install e2fsprogs' or 'sudo yum install e2fsprogs' or 'sudo dnf install e2fsprogs'"
            elif [[ "$cmd" == "findmnt" ]]; then
                 echo "Try: 'sudo apt update && sudo apt install util-linux' or 'sudo yum install util-linux' or 'sudo dnf install util-linux'"
            fi
            found_all_commands=0
        fi
    fi
done

if [[ $found_all_commands -eq 0 ]]; then
    log_message "One or more required commands were not found. Exiting."
    exit 1
fi


# Identify potential drives using lsblk JSON output and jq
log_message "Scanning for available block devices using lsblk and jq..."

# Get the parent device of the root filesystem
root_parent_device=""
root_source=$(findmnt -n -o SOURCE /)
if [[ -n "$root_source" ]]; then
    # Try getting pkname first (e.g., nvme0n1 from nvme0n1p1)
    root_parent_device=$(lsblk -no pkname "$root_source" 2>/dev/null)
    # If pkname is empty (e.g., root on /dev/sda), get kname (e.g., sda)
    if [[ -z "$root_parent_device" ]]; then
        root_parent_device=$(lsblk -no kname "$root_source" 2>/dev/null)
    fi
fi

if [[ -z "$root_parent_device" ]]; then
     log_message "Warning: Could not reliably determine the root filesystem's parent device. Filtering might be incomplete."
else
     log_message "Root filesystem appears to be on a partition of or directly on: ${root_parent_device}"
fi


# Run lsblk with sudo to ensure visibility of all devices
# Removed PATH from output as it wasn't used and can be derived from NAME
available_drives_json=$(sudo lsblk -dJb -o NAME,SIZE,MODEL,SERIAL,TYPE,VENDOR,PKNAME,TRAN) # Added TRAN, use bytes (-b)
if [[ $? -ne 0 || -z "$available_drives_json" ]]; then
    log_message "Error: Failed to get drive list from lsblk. Check 'sudo lsblk -dJb -o NAME,SIZE,MODEL,SERIAL,TYPE,VENDOR,PKNAME,TRAN' manually."
    exit 1
fi

echo "--------------------------------------------------"
echo "Available Block Devices (Potential Targets):"
echo "--------------------------------------------------"
# Removed ID Path column header
printf "%-5s %-15s %-12s %-10s %-20s %-s\n" "Index" "Device" "Size (GB)" "Transport" "Model" "Serial"

index=0
declare -A drive_map # Associative array to map index to device path
declare -A drive_id_map # Associative array to map index to unique drive identifier

# Use jq to parse the JSON output
# Select devices where type is 'disk' and name is not the root parent device
# Output format: index\t/dev/name\tsize_gb\ttransport\tmodel\tserial\tunique_id_sanitized
# Removed the problematic dev_id_path lookup
while IFS=$'\t' read -r idx dev_path dev_size_gb dev_tran dev_model dev_serial unique_id_sanitized; do
    # Basic check if line seems valid (has an index)
    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then continue; fi

    # Print without ID Path
    printf "%-5s %-15s %-12s %-10s %-20s %-s\n" "$idx" "$dev_path" "$dev_size_gb" "$dev_tran" "$dev_model" "$dev_serial"
    drive_map[$idx]="$dev_path"
    drive_id_map[$idx]="$unique_id_sanitized"
    # Index is implicitly tracked by the number of valid lines processed by jq/awk below
    ((index++))

done < <(echo "$available_drives_json" | jq -r --arg root_dev "$root_parent_device" '
    .blockdevices[] |
    # Filter: type=="disk" and name != root_parent_device and pkname != root_parent_device (if pkname exists and root_dev is not empty)
    select(
        .type == "disk" and
        ( $root_dev == "" or ( .name != $root_dev and (.pkname == null or .pkname != $root_dev) ) )
    ) |
    # Extract fields, handle nulls gracefully
    ( .name // "N/A" ) as $name |
    ( "/dev/" + $name ) as $path | # Construct path directly
    ( .size // 0 ) as $size_bytes |
    ( ($size_bytes / (1000*1000*1000)) | round ) as $size_gb | # Calculate GB (use 1000 base for disk size)
    ( .tran // "N/A" ) as $transport |
    ( .model // "N/A" ) as $model |
    ( .serial // "N/A" ) as $serial |
    # Create unique ID: prefer serial, fallback to model-name, sanitize
    ( ($serial | select(. != null and . != "N/A")) // ($model | select(. != null and . != "N/A")) // "unknown" ) as $base_id |
    ( $base_id + "-" + $name ) as $unique_id |
    ( $unique_id | gsub("[ /]"; "_") | gsub("[^a-zA-Z0-9_-]"; "") ) as $sanitized_id | # Further sanitize for filenames
    # Output tab-separated values: index needs to be generated outside jq
    # Removed id_path from output array
    [ $path, $size_gb, $transport, $model, $serial, $sanitized_id ] | @tsv
' | awk -v OFS='\t' '{print NR-1, $0}' # Add index starting from 0
)


echo "--------------------------------------------------"

# Check if any drives were found after filtering
if [[ $index -eq 0 ]]; then
    log_message "No suitable target drives found after filtering (Type 'disk', excluding root device '${root_parent_device:-none specified}'). Check script filters or if drives are visible to 'lsblk'."
    log_message "Raw lsblk JSON output (first 10 lines for brevity):"
    echo "$available_drives_json" | head -n 10 | while IFS= read -r line; do log_message "$line"; done # Log lines individually
    exit 0
fi


# Get user selection
echo "Enter the indices of the drives you want to test, separated by spaces (e.g., '0 2 3')."
read -p "Selected indices: " -a selected_indices

# Validate selection
target_drives=()
target_drive_ids=()
valid_selection=0
for idx in "${selected_indices[@]}"; do
    # Check if input is numeric first
    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
        echo "Warning: Non-numeric input '$idx' ignored."
        continue
    fi
    # Check if index exists as a key in the map
    if [[ -v drive_map[$idx] ]]; then
        target_drives+=("${drive_map[$idx]}")
        target_drive_ids+=("${drive_id_map[$idx]}")
        valid_selection=1
    else
        echo "Warning: Invalid index '$idx' ignored (not in the list above)."
    fi
done

if [[ $valid_selection -eq 0 || ${#target_drives[@]} -eq 0 ]]; then
    log_message "No valid drives selected or selection was empty. Exiting."
    exit 0
fi

# *** CRITICAL SAFETY CONFIRMATION ***
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "You have selected the following drives for DESTRUCTIVE testing:"
for i in "${!target_drives[@]}"; do
    # Re-fetch details for confirmation display if needed (using drive_map key)
    # This assumes indices in target_drives correspond to the printed list
    idx_for_confirm=""
    for key in "${!drive_map[@]}"; do
        if [[ "${drive_map[$key]}" == "${target_drives[$i]}" ]]; then
            idx_for_confirm=$key
            break
        fi
    done
    echo "  - Index: ${idx_for_confirm:-?}, Path: ${target_drives[$i]}, ID: ${target_drive_ids[$i]}"
done
echo "The 'badblocks -wsvb 4096' test WILL ERASE ALL DATA on these drives." # Updated command here
echo "Verify the paths and indices carefully!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
read -p "Are you absolutely sure you want to proceed? (Type 'YES' to confirm): " confirmation
echo ""

if [[ "$confirmation" != "YES" ]]; then
    log_message "User aborted the operation. Exiting."
    exit 0
fi

# *** SECOND CONFIRMATION ***
read -p "Final confirmation: Destructive testing will begin. Proceed? (Type 'CONFIRM DESTRUCTIVE TEST' to continue): " final_confirmation
echo ""

if [[ "$final_confirmation" != "CONFIRM DESTRUCTIVE TEST" ]]; then
    log_message "User aborted the operation at final confirmation. Exiting."
    exit 0
fi


# Start tests in parallel
log_message "Starting tests on selected drives in parallel..."
pids=()
for i in "${!target_drives[@]}"; do
    drive_path="${target_drives[$i]}"
    drive_id="${target_drive_ids[$i]}"
    log_message "Launching test process for ${drive_path} (ID: ${drive_id})..."
    # Run test_drive function in the background
    test_drive "$drive_path" "$drive_id" &
    pids+=($!) # Store the process ID
done

# Wait for all background processes to complete
log_message "Waiting for all tests to complete. This may take a very long time..."
final_exit_code=0
wait_count=${#pids[@]}
completed_count=0

# Loop until all background jobs we started are done
while [[ $completed_count -lt $wait_count ]]; do
    # Wait for any background process specifically from our list to finish
    # Using 'wait -p var pid' might be better if available, but 'wait -n' is more portable
    wait -n # Waits for the next background job to finish
    exit_code=$?
    completed_count=$((completed_count + 1))
    # We don't easily know *which* PID finished with 'wait -n', just that one did.
    log_message "A test process finished (Exit Code: $exit_code). ${completed_count} of ${wait_count} completed."
    if [[ $exit_code -ne 0 ]]; then
        final_exit_code=1 # Mark that at least one test failed or had errors
    fi
    # Add a small sleep just in case wait -n returns immediately in some edge cases
    # sleep 0.1
done


log_message "All test processes launched by this script have completed."
echo "--------------------------------------------------"
echo "Test Summary:"
echo "--------------------------------------------------"
all_summaries_found=1
for i in "${!target_drives[@]}"; do
    drive_path="${target_drives[$i]}"
    drive_id="${target_drive_ids[$i]}"
    summary_file="${MAIN_REPORT_DIR}/${drive_id}/summary.txt"
    if [[ -f "$summary_file" ]]; then
        result=$(grep "Overall Result:" "$summary_file" | awk '{print $NF}')
        echo "Drive: ${drive_path} (ID: ${drive_id}) - Result: ${result}"
    else
        echo "Drive: ${drive_path} (ID: ${drive_id}) - Result: UNKNOWN (Summary file not found!)"
        final_exit_code=1 # Missing summary implies failure or script error
        all_summaries_found=0
    fi
done
echo "--------------------------------------------------"
log_message "Detailed reports are located in: ${MAIN_REPORT_DIR}"

if [[ $all_summaries_found -eq 0 ]]; then
     log_message "Warning: One or more summary files were missing."
fi

if [[ $final_exit_code -ne 0 ]]; then
    log_message "Script finished with one or more test failures, errors, or missing reports."
else
    log_message "Script finished. All selected drives completed tests (check summaries for pass/fail details)."
fi

exit $final_exit_code

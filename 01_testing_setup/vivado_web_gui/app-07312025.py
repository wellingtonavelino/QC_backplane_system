from flask import Flask, render_template, request, redirect, url_for, Response, request
import subprocess
import threading
import os
import queue
import pandas as pd
import time
import tempfile
import os
import socket

app = Flask(__name__)

# Global state
vivado_path = ""
script_name = ""
output_queue = queue.Queue()
status = "Idle"
running = False
result_table = ""

# Helper to show Python-side logs in browser
def log_to_gui(message):
    output_queue.put(f"[PYTHON] {message}")

def highlight_ber(val):
    try:
        return 'background-color: yellow' if val > 1e-6 else ''
    except:
        return ''

def format_dataframe(out):
    df = pd.DataFrame(out)
    df['ber'] = df['ber'].astype(float)
    df['errors'] = pd.to_numeric(df['errors'], errors='coerce').astype('int64')

    styled_df = (
        df.style
        .applymap(highlight_ber, subset=['ber'])
        .format({
            'ber': '{:.2e}',
            'errors': lambda x: f"{x:,}" if x < 10000 else f"{x//1000}K"
        })
        .set_properties(**{'text-align': 'center'})
        .set_table_styles([
            {'selector': 'th', 'props': [('text-align', 'center')]},
            {'selector': 'td', 'props': [('text-align', 'center'), ('font-size', '8pt')]}
        ])
    )
    return styled_df.to_html()
    
def parse_latest_results_from_log(log_path):
    with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    # Find the last "IBERT QC BER Log" section
    start_idx = None
    for i in reversed(range(len(lines))):
        if "IBERT QC BER Log" in lines[i]:
            start_idx = i
            break

    if start_idx is None:
        return None

    # Skip header and get the table lines
    rows = []
    for line in lines[start_idx + 1:]:
        line = line.strip()
        if line == "" or line.startswith("==="):  # end of block
            break
        if "Serial,from Board" in line:
            continue
        if "," in line:
            rows.append(line.split(","))

    if not rows:
        return None

    df = pd.DataFrame(rows, columns=["Serial", "From", "To", "BER", "Errors"])
    df["BER"] = pd.to_numeric(df["BER"], errors="coerce")
    df["Errors"] = pd.to_numeric(df["Errors"], errors="coerce")
    return df


# def list_tcl_files():
    # return [f for f in os.listdir() if f.endswith(".tcl")]
def list_script_files():
    valid_exts = (".tcl", ".sh", ".xsct")
    return [f for f in os.listdir() if f.endswith(valid_exts)]
   

def is_hw_server_running(host='127.0.0.1', port=3121):
    """Check if hw_server is listening on localhost:3121."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        try:
            s.connect((host, port))
            return True
        except (socket.timeout, ConnectionRefusedError):
            return False

def find_xsct_target_for_serial(vivado_path, vitis_path, serial_number):
    """
    Finds the XSCT target ID for a given USB serial number from Vivado.
    Returns the target ID or None if not found.
    """
    serial_number = serial_number.strip()

    # --- Step 1: Vivado TCL to get serial numbers ---
    vivado_tcl = f"""
    open_hw
    connect_hw_server
    foreach tgt [get_hw_targets] {{
        set ser [get_property JTAG_SERIAL_NUMBER $tgt]
        puts "$ser,$tgt"
    }}
    exit
    """

    with tempfile.NamedTemporaryFile(mode="w", suffix=".tcl", delete=False) as tf:
        tf.write(vivado_tcl)
        vivado_tcl_path = tf.name

    result = subprocess.run(
        [vivado_path, "-mode", "batch", "-nolog", "-nojournal", "-source", vivado_tcl_path],
        capture_output=True, text=True
    )
    vivado_output = result.stdout.splitlines()

    matched_vivado_target = None
    for line in vivado_output:
        if serial_number in line:
            matched_vivado_target = line.strip().split(",")[1]
            break

    if not matched_vivado_target:
        return None

    # --- Step 2: XSCT to list targets ---
    xsct_tcl = """
    connect -url tcp:127.0.0.1:3121
    targets
    exit
    """

    xsct_path = os.path.join(vitis_path, "xsct.bat")  # Windows
    with tempfile.NamedTemporaryFile(mode="w", suffix=".tcl", delete=False) as tf:
        tf.write(xsct_tcl)
        xsct_tcl_path = tf.name

    result = subprocess.run([xsct_path, xsct_tcl_path], capture_output=True, text=True)
    xsct_output = result.stdout.splitlines()

    # Find Cortex-A53 #0 ID (example target for programming)
    for line in xsct_output:
        if "Cortex-A53" in line and "#0" in line:
            return line.strip().split()[0]

    return None




def run_vivado(vivado_exec, script, script_mode):

    global status, running, output_queue, result_table

    running = True
    status = f"Running {script}"
    # output_queue.queue.clear()
    result_table = ""

    try:
        log_to_gui("=== [PYTHON] Starting process ===")
        log_to_gui(f"[PYTHON] Preparing to run script: {script}")
        log_to_gui(f"[PYTHON] Mode: {'QSPI Flash (via xsct)' if script_mode == 'flash' else 'BER Test'}")

        _, ext = os.path.splitext(script)
        ext = ext.lower()

        # -------------------------
        # QSPI FLASH MODE
        # -------------------------
        if script_mode == "flash":
            log_to_gui("[PYTHON] Script type: XSCT (Vitis scripting)")
            
            serial_number = request.form.get("serial_number", "").strip()
            vitis_bin_dir = os.path.join(os.path.dirname(vivado_exec), "..", "bin")

            log_to_gui(f"🔍 Looking up XSCT target for board serial {serial_number}...")
            target_id = find_xsct_target_for_serial(vivado_exec, vitis_bin_dir, serial_number)

            if not target_id:
                log_to_gui("❌ Could not find matching board for serial.")
                running = False
                return

            log_to_gui(f"✅ Matched to XSCT target ID {target_id}")

            # Inject target_id into a temp TCL
            with tempfile.NamedTemporaryFile(mode="w", suffix=".tcl", delete=False) as tf:
                tf.write(f"set target_id {target_id}\n")
                with open(script, "r") as orig:
                    tf.write(orig.read())
                temp_tcl_path = tf.name

            # Generate temporary .bat that calls Vitis environment and then xsct
            with tempfile.NamedTemporaryFile(mode="w", suffix=".bat", delete=False) as temp_bat:
                temp_bat.write(f'call "{vivado_exec}"\n')  # This must be Vitis settings64.bat
                temp_bat.write(f'xsct "{script}"\n')
                temp_bat_path = temp_bat.name

            command = ["cmd", "/c", temp_bat_path]
        # -------------------------
        # BER TEST MODE
        # -------------------------
        elif ext == ".tcl":
            log_to_gui("[PYTHON] Script type: TCL (Vivado batch mode)")
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix=".tcl") as temp_tcl:
                temp_tcl.write(f'source "{script}"\n')
                temp_tcl_path = temp_tcl.name
            command = [vivado_exec, "-mode", "batch", "-source", temp_tcl_path]

        elif ext == ".py":
            log_to_gui("[PYTHON] Script type: Python")
            command = ["python", script]

        elif ext == ".sh":
            log_to_gui("[PYTHON] Script type: Shell")
            command = ["bash", script]

        elif ext == ".xsct":
            log_to_gui("[PYTHON] Script type: XSCT (Vitis scripting)")
            command = ["xsct", script]

        else:
            raise ValueError(f"Unsupported script type: {ext}")

        log_to_gui(f"[PYTHON] Launching: {' '.join(command)}")

        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace"
        )

        log_to_gui("[PYTHON] Waiting for process to complete...")
        stdout_data, _ = process.communicate()
        return_code = process.returncode

        success_marker_found = False
        for line in stdout_data.splitlines():
            output_queue.put(f"[SCRIPT] {line}")
            if "SUCCESS: Flash programming completed!" in line:
                success_marker_found = True

        output_queue.put(f">>> Process finished with code {return_code}")
        log_to_gui(f"[PYTHON] Process completed with code {return_code}")

        if script_mode == "ber":
            df = parse_latest_results_from_log("ibert_qc_ber.log")
            if df is not None:
                df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]
                result_table = format_dataframe(df)
                log_to_gui("[PYTHON] Table generated.")
            else:
                result_table = None
                log_to_gui("[PYTHON] No BER data found.")
        else:
            result_table = None
            if success_marker_found:
                log_to_gui("[PYTHON] ✅ Flash programming was successful.")
            else:
                log_to_gui("[PYTHON] ⚠️ Could not confirm programming success. Check logs.")
            log_to_gui("[PYTHON] Skipping BER table generation (mode = flash).")

        status = f"Done: {script}"
        output_queue.put("[PYTHON] === END OF LOG ===")

    except Exception as e:
        output_queue.put(f"[PYTHON][EXCEPTION] {e}")
        status = f"Error: {e}"

    running = False
    log_to_gui("=== [PYTHON] Script complete. running=False ===")

@app.route("/", methods=["GET", "POST"])
def home():
    global vivado_path, script_name, status, running, result_table
    #script_list = list_tcl_files()
    script_list = list_script_files()
    
    script_mode = request.form.get("script_mode", "ber")
    
    if not is_hw_server_running():
        status = "⚠️ Warning: hw_server is not running on localhost:3121"


    serial_number = request.form.get("serial_number", "").strip()
    if serial_number and not re.match(r"^\d{4}$", serial_number):
        status = "Error: Serial number must be exactly 4 digits"


    if request.method == "POST":
        vivado_path = request.form.get("vivado_path")
        script_name = request.form.get("tcl_script")

        if not os.path.isfile(vivado_path):
            status = f"Error: Vivado not found: {vivado_path}"
        elif script_name not in script_list:
            status = "Error: Tcl script not selected or invalid."
        else:
            status = "Starting..."
            #threading.Thread(target=run_vivado, args=(vivado_path, script_name), daemon=True).start()
            threading.Thread(target=run_vivado, args=(vivado_path, script_name, script_mode), daemon=True).start()

        return redirect(url_for("home"))

    return render_template("index.html",
                           script_list=script_list,
                           vivado_path=vivado_path,
                           status=status,
                           running=running,
                           result_table=result_table)

@app.route("/status")
def check_status():
    return {"running": running}

@app.route("/logs")
def logs():
    def stream():
        last_seen = time.time()
        while True:
            try:
                line = output_queue.get(timeout=1)
                yield f"data: {line}\n\n"
                last_seen = time.time()
            except queue.Empty:
                if not running and (time.time() - last_seen > 5):
                    break
    return Response(stream(), mimetype="text/event-stream")

@app.route('/shutdown')
def shutdown():
    output_queue.put("[PYTHON] Shutdown requested...")
    func = request.environ.get('werkzeug.server.shutdown')
    if func is None:
        output_queue.put("[PYTHON] ERROR: Not running with the Werkzeug Server.")
        return "<h2 style='color:red;'>ERROR: Not running with the Werkzeug Server.</h2>"
    func()
    return "<h2>Server shutting down...</h2>"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True, threaded=True)

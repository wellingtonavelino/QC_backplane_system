from flask import Flask, render_template, request, redirect, url_for, Response
import subprocess
import threading
import os
import queue
import pandas as pd
import time
import tempfile
import socket
import re

app = Flask(__name__)

# Global state
vivado_path = ""
script_name = ""
output_queue = queue.Queue()
status = "Idle"
running = False
result_table = ""
script_mode_selected = "ber"


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

    start_idx = None
    for i in reversed(range(len(lines))):
        if "IBERT QC BER Log" in lines[i]:
            start_idx = i
            break

    if start_idx is None:
        return None

    rows = []
    for line in lines[start_idx + 1:]:
        line = line.strip()
        if line == "" or line.startswith("==="):
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

def list_script_files():
    valid_exts = (".tcl", ".sh", ".xsct")
    return [f for f in os.listdir() if f.endswith(valid_exts)]

def is_hw_server_running(host='127.0.0.1', port=3121):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        try:
            s.connect((host, port))
            return True
        except (socket.timeout, ConnectionRefusedError):
            return False
            
def resolve_vitis_settings_from_input(user_path: str):
    """
    Accept these arguments:
      - direct path for settings64.bat
      - path for the Vitis folder  (ex: C:\\Xilinx\\Vitis\\2022.2)
      - path for vivado.exe (It is not for flash option)
    Return full path of settings64.bat (if exists).
    """
    if not user_path:
        return None

    p = user_path.strip().strip('"')

    # Case 1: User already specify settings64.bat
    if p.lower().endswith("settings64.bat") and os.path.isfile(p):
        return p

    # Case 2: User already specify Vitis folder
    # Ex: C:\Xilinx\Vitis\2022.2  -> C:\Xilinx\Vitis\2022.2\settings64.bat
    if os.path.isdir(p):
        candidate = os.path.join(p, "settings64.bat")
        if os.path.isfile(candidate):
            return candidate

    # Case 3: User uses vivado.exe or vitis.exe etc (não é settings)
    # Try find directories and settings64.bat
    base_dir = os.path.dirname(p)
    for _ in range(4):
        candidate = os.path.join(base_dir, "settings64.bat")
        if os.path.isfile(candidate):
            return candidate
        base_dir = os.path.dirname(base_dir)

    return None


def run_vivado(vivado_exec, script, script_mode, serial_number):
    global status, running, output_queue, result_table

    running = True
    status = f"Running {script}"
    result_table = ""

    try:
        log_to_gui("=== [PYTHON] Starting process ===")
        log_to_gui(f"[PYTHON] Preparing to run script: {script}")
        log_to_gui(f"[PYTHON] Mode: {'QSPI Flash (via xsct)' if script_mode == 'flash' else 'BER Test'}")
        log_to_gui(f"[PYTHON] Target Serial Number: {serial_number}")

        _, ext = os.path.splitext(script)
        ext = ext.lower()

        if script_mode == "flash":
            log_to_gui("[PYTHON] Script type: XSCT (Vitis scripting)")
            vitis_settings = resolve_vitis_settings_from_input(vivado_exec)
            if not vitis_settings:
                raise FileNotFoundError(
                    "Could not find Vitis settings64.bat.\n"
                    "Please set 'Vivado/Vitis Executable Path' to something like:\n"
                    r"  C:\Xilinx\Vitis\2022.2\settings64.bat"
                )

            log_to_gui(f"[PYTHON] Using Vitis environment: {vitis_settings}")

            with tempfile.NamedTemporaryFile(mode="w", suffix=".bat", delete=False) as temp_bat:
                temp_bat.write(f'call "{vitis_settings}"\n')
                temp_bat.write(f'xsct "{script}"\n')
                temp_bat_path = temp_bat.name

            command = ["cmd", "/c", temp_bat_path]


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
        # stdout_data, _ = process.communicate()
        for line in process.stdout:
            output_queue.put(f"[SCRIPT] {line.rstrip()}")
        return_code = process.wait()
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

    script_list = list_script_files()
    # script_mode = request.form.get("script_mode", "ber")
    global script_mode_selected
    script_mode = request.form.get("script_mode", script_mode_selected)
    selected_script = request.form.get("tcl_script", script_name)


    if not is_hw_server_running():
        status = "⚠️ Warning: hw_server is not running on localhost:3121"

    serial_number = request.form.get("serial_number", "").strip()
    if serial_number and not re.match(r"^\d{4}$", serial_number):
        status = "Error: Serial number must be exactly 4 digits"

    if request.method == "POST":
        vivado_path = request.form.get("vivado_path")
        script_name = request.form.get("tcl_script")

        if not os.path.isfile(vivado_path):
            status = f"Error: Vivado/Vitis not found: {vivado_path}"
        elif script_name not in script_list:
            status = "Error: Script not selected or invalid."
        else:
            status = "Starting..."
            threading.Thread(
                target=run_vivado,
                args=(vivado_path, script_name, script_mode, serial_number),
                daemon=True
            ).start()
        
        script_mode_selected = script_mode
        # script_name = script_mode

        return redirect(url_for("home"))

    return render_template("index.html",
                       script_list=script_list,
                       vivado_path=vivado_path,
                       status=status,
                       running=running,
                       result_table=result_table,
                       script_mode=script_mode_selected,
                       tcl_script=script_name)


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

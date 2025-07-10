from flask import Flask, render_template, request, redirect, url_for, Response, request
import subprocess
import threading
import os
import queue
import pandas as pd
import time
import tempfile
import os

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
    valid_exts = (".tcl", ".py", ".sh")
    return [f for f in os.listdir() if f.endswith(valid_exts)]


def run_vivado(vivado_exec, script):
    import tempfile
    import os

    global status, running, output_queue, result_table

    running = True
    status = f"Running {script}"
    output_queue.queue.clear()
    result_table = ""

    try:
        log_to_gui("=== [PYTHON] Starting process ===")
        log_to_gui(f"[PYTHON] Preparing to run script: {script}")

        _, ext = os.path.splitext(script)
        ext = ext.lower()

        # Determine the command based on script type
        if ext == ".tcl":
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

        for line in stdout_data.splitlines():
            output_queue.put(f"[SCRIPT] {line}")

        output_queue.put(f">>> Process finished with code {return_code}")
        log_to_gui(f"[PYTHON] Process completed with code {return_code}")

        # Try to parse BER results if log file exists
        df = parse_latest_results_from_log("ibert_qc_ber.log")
        if df is not None:
            df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]
            result_table = format_dataframe(df)
        else:
            result_table = None

        status = f"Done: {script}"
        log_to_gui("[PYTHON] Table generated.")

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
            threading.Thread(target=run_vivado, args=(vivado_path, script_name), daemon=True).start()
        return redirect(url_for("home"))

    return render_template("index.html",
                           script_list=script_list,
                           vivado_path=vivado_path,
                           status=status,
                           running=running,
                           result_table=result_table)

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
    log_queue.put("[PYTHON] [PYTHON] Shutdown requested...")
    func = request.environ.get('werkzeug.server.shutdown')
    if func is None:
        raise RuntimeError('Not running with the Werkzeug Server')
    func()
    return "<h2>Server shutting down...</h2>"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True, threaded=True)

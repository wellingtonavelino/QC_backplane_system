from flask import Flask, render_template, redirect, url_for
import subprocess
import threading

app = Flask(__name__)

def run_tcl():
    subprocess.call(["vivado", "-mode", "tcl", "-source", "your_script.tcl"])

@app.route("/")
def home():
    return render_template("index.html")

@app.route("/run")
def run():
    threading.Thread(target=run_tcl).start()
    return redirect(url_for('home'))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

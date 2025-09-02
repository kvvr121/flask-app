# flask-app

python -m venv flask-env
✅ What it does:
This creates a new virtual environment called flask-env in your current directory.
🔍 Breakdown:
* python: Uses your current Python interpreter (you can control which with pyenv)
* -m venv: Runs the venv module to create a virtual environment
* flask-env: The name (and directory) where the environment will be stored
💾 Result:
This creates a folder named flask-env/ containing a full isolated Python environment, including:
* Its own Python binary
* Its own pip
* A place to install packages (like Flask) without affecting your system Python

⚙️ source flask-env/bin/activate
✅ What it does:
This activates the virtual environment, switching your terminal to use that isolated environment.
🔍 Breakdown:
* source: A shell command that runs a script in the current shell (not a subshell)
* flask-env/bin/activate: The activation script inside the virtual environment
💡 After running this:
* Your shell prompt changes to show (flask-env)
* The python and pip commands now refer to the versions inside flask-env
* Any packages you install with pip install go into that environment only

🧪 Why use virtual environments?
They help you:
* Avoid version conflicts between projects
* Keep your global Python clean
* Use different Python versions with pyenv + venv

🔁 Deactivate when done:
To leave the virtual environment:
bash
CopyEdit
deactivate
This returns your terminal to the system/default Python.


*********************


from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    return "Hello from Flask!"

@app.route('/about')
def about():
    return "This is the About page."

if __name__ == '__main__':
    app.run(debug=True)

**********************

from flask import Flask
* You're importing the Flask class from the flask package.
* This class is the core of your web application — it represents the app itself.

app = Flask(__name__)
* This creates an instance of your Flask application.
* __name__ is a Python built-in variable that equals "__main__" when you run the file directly.
* Flask uses __name__ to figure out where to look for things like templates or static files.

@app.route('/')
* This is a decorator that tells Flask:When someone visits the / URL (the home page), run the function below it.

def home():
python
CopyEdit
return "Hello from Flask!"
* This function is the view for the / route.
* It returns the response to be sent to the browser — in this case, a simple text string.

@app.route('/about')
* Another route decorator, this time for the URL /about.

def about():
python
CopyEdit
return "This is the About page."
* The response for the /about URL.

if __name__ == '__main__':
* This block checks if you're running this script directly, not importing it as a module.
* It's a standard Python idiom to ensure the app only runs when executed, not when imported.

app.run(debug=True)
* This starts the Flask development server.
* debug=True enables:
    * Automatic code reloading when you save
    * A debugger in the browser for Python errors

**********************

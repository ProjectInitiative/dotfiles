import FreeCAD
import FreeCADGui
import ImportGui
import os
from PySide import QtGui
import traceback

def safe_save_document(document):
    try:
        document.save()
        FreeCAD.Console.PrintMessage("Document saved successfully.\n")
        return True
    except Exception as e:
        FreeCAD.Console.PrintError(f"Error saving document: {str(e)}\n")
        return False

def export_configurations(document):
    try:
        file_path = document.FileName
        if not file_path:
            FreeCAD.Console.PrintError("Document has not been saved yet. Skipping export.\n")
            return

        directory, full_name = os.path.split(file_path)
        base_name = os.path.splitext(full_name)[0]

        for obj in document.Objects:
            if obj.TypeId == "PartDesign::Body":
                FreeCAD.Console.PrintMessage(f"PartDesign::Body found: {obj.Name}\n")
                
                if hasattr(obj, 'Configuration'):
                    configurations = obj.getEnumerationsOfProperty('Configuration')
                    FreeCAD.Console.PrintMessage(f"Configurations: {configurations}\n")
                    
                    for config_name in configurations:
                        try:
                            obj.Configuration = config_name
                            document.recompute()
                            
                            export_name = f"{base_name}_{obj.Name}_{config_name}.step"
                            export_path = os.path.join(directory, export_name)
                            
                            ImportGui.export([obj], export_path)
                            FreeCAD.Console.PrintMessage(f"Exported: {export_name}\n")
                        except Exception as config_error:
                            FreeCAD.Console.PrintError(f"Error exporting configuration {config_name}: {str(config_error)}\n")
                else:
                    FreeCAD.Console.PrintMessage(f"Object {obj.Name} does not have Configuration property. Exporting default state.\n")
                    try:
                        export_name = f"{base_name}_{obj.Name}_default.step"
                        export_path = os.path.join(directory, export_name)
                        
                        ImportGui.export([obj], export_path)
                        FreeCAD.Console.PrintMessage(f"Exported default state: {export_name}\n")
                    except Exception as export_error:
                        FreeCAD.Console.PrintError(f"Error exporting default state for {obj.Name}: {str(export_error)}\n")
        FreeCAD.Console.PrintMessage("Export process completed.\n")
    except Exception as e:
        FreeCAD.Console.PrintError(f"Error in export process: {str(e)}\n")
        FreeCAD.Console.PrintError(f"Traceback: {traceback.format_exc()}\n")

class SafeSaveAndExportCommand:
    def GetResources(self):
        return {'Pixmap': 'Std_Save',
                'MenuText': 'Safe Save and Export',
                'ToolTip': 'Safely save document and attempt to export configurations'}

    def Activated(self):
        FreeCAD.Console.PrintMessage("SafeSaveAndExport command activated\n")
        doc = FreeCAD.ActiveDocument
        if doc:
            # Always attempt to save the document first
            if safe_save_document(doc):
                # Only attempt to export if the save was successful
                try:
                    export_configurations(doc)
                except Exception as export_error:
                    FreeCAD.Console.PrintError(f"Error during export, but document was saved: {str(export_error)}\n")
            else:
                FreeCAD.Console.PrintError("Document could not be saved. Export was not attempted.\n")
        else:
            FreeCAD.Console.PrintError("No active document to save\n")

    def IsActive(self):
        return FreeCAD.ActiveDocument is not None

def test_command():
    FreeCAD.Console.PrintMessage("Testing SafeSaveAndExport command\n")
    cmd = SafeSaveAndExportCommand()
    cmd.Activated()

def run():
    FreeCAD.Console.PrintMessage("Registering SafeSaveAndExport command\n")
    FreeCADGui.addCommand('SafeSaveAndExport', SafeSaveAndExportCommand())

    # Add the custom command to the File menu and toolbar, but do not replace the original Save command
    try:
        FreeCAD.Console.PrintMessage("Attempting to add SafeSaveAndExport to UI\n")
        mw = FreeCADGui.getMainWindow()
        if mw:
            # Create an instance of our command
            safe_save_export_cmd = SafeSaveAndExportCommand()
        
            # Add to File menu
            fileMenu = mw.findChild(QtGui.QMenu, '&File')
            if fileMenu:
                FreeCAD.Console.PrintMessage("Adding to File menu\n")
                action = QtGui.QAction('Safe Save and Export', mw)
                action.triggered.connect(lambda: FreeCAD.Console.PrintMessage("Menu item clicked\n"))
                action.triggered.connect(safe_save_export_cmd.Activated)
                fileMenu.addAction(action)
            else:
                FreeCAD.Console.PrintWarning("File menu not found\n")
        
            # Add to Standard toolbar
            toolbar = FreeCADGui.getMainWindow().findChild(QtGui.QToolBar, 'File')
            if toolbar:
                FreeCAD.Console.PrintMessage("Adding to toolbar\n")
                action = QtGui.QAction(QtGui.QIcon(':/icons/document-save.svg'), 'Safe Save and Export', mw)
                action.triggered.connect(lambda: FreeCAD.Console.PrintMessage("Toolbar item clicked\n"))
                action.triggered.connect(safe_save_export_cmd.Activated)
                toolbar.addAction(action)
            else:
                FreeCAD.Console.PrintWarning("Toolbar not found\n")
        
            FreeCAD.Console.PrintMessage("SafeSaveAndExport command added to File menu and toolbar.\n")
        else:
            FreeCAD.Console.PrintWarning("Main window not found\n")
    except Exception as e:
        FreeCAD.Console.PrintError(f"An error occurred while setting up the SafeSaveAndExport command: {str(e)}\n")
        FreeCAD.Console.PrintError(f"Traceback: {traceback.format_exc()}\n")



if __name__ == '__main__':
    run()
    # Uncomment the next line to test the command when the macro runs
    # test_command()

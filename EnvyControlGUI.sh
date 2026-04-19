#!/usr/bin/env python3
import sys
import subprocess
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QCheckBox, QGroupBox, QMessageBox,
    QSystemTrayIcon, QMenu
)
from PyQt6.QtCore import Qt, QProcess, QTimer
from PyQt6.QtGui import QIcon, QAction

class EnvyControlGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("EnvyControl GUI")
        self.setFixedSize(460, 420)
        
        self.selected_mode = None
        self.process = None  # Para evitar que se destruya el QProcess prematuramente
        
        self.current_mode = self.get_current_mode()
        
        self.init_ui()
        self.create_tray_icon()
        
        # Actualizar estado inicial
        self.update_status_label()

    def get_current_mode(self):
        """Obtiene el modo actual de EnvyControl"""
        try:
            result = subprocess.run(["envycontrol", "-q"], 
                                  capture_output=True, text=True, timeout=6)
            if result.returncode != 0:
                return "error"
            
            output = result.stdout.strip().lower()
            if "integrated" in output:
                return "integrated"
            elif "hybrid" in output:
                return "hybrid"
            elif "nvidia" in output:
                return "nvidia"
            return "unknown"
        except FileNotFoundError:
            return "not_installed"
        except Exception:
            return "error"

    def update_status_label(self):
        mode = self.current_mode
        if mode == "not_installed":
            text = "<b style='color:red'>¡EnvyControl no está instalado!</b>"
        elif mode == "error":
            text = "<b style='color:orange'>Error al detectar el modo</b>"
        else:
            text = f"Modo actual: <b>{mode.upper()}</b>"
        
        self.status_label.setText(text)

    def init_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setSpacing(18)
        layout.setContentsMargins(20, 20, 20, 20)

        # Estado actual
        self.status_label = QLabel()
        self.status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.status_label.setStyleSheet("font-size: 14px;")
        layout.addWidget(self.status_label)

        # Botones principales
        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(12)

        self.btn_integrated = QPushButton("Integrated\n(Ahorro de batería)")
        self.btn_hybrid = QPushButton("Hybrid\n(Recomendado)")
        self.btn_nvidia = QPushButton("NVIDIA\n(Máximo rendimiento)")

        for btn in (self.btn_integrated, self.btn_hybrid, self.btn_nvidia):
            btn.setMinimumHeight(85)
            btn.setStyleSheet("font-size: 13px; text-align: center;")
            btn_layout.addWidget(btn)

        layout.addLayout(btn_layout)

        # Opciones avanzadas
        adv_group = QGroupBox("Opciones avanzadas")
        adv_layout = QVBoxLayout()
        
        self.chk_rtd3 = QCheckBox("Habilitar RTD3 (mejor gestión de energía en Hybrid)")
        self.chk_force_comp = QCheckBox("Force Composition Pipeline (reduce tearing en NVIDIA)")
        self.chk_coolbits = QCheckBox("Coolbits 24 (para overclock y control de ventiladores)")
        
        adv_layout.addWidget(self.chk_rtd3)
        adv_layout.addWidget(self.chk_force_comp)
        adv_layout.addWidget(self.chk_coolbits)
        adv_group.setLayout(adv_layout)
        layout.addWidget(adv_group)

        # Botón de aplicar
        self.btn_apply = QPushButton("Aplicar cambio y reiniciar el sistema")
        self.btn_apply.setStyleSheet("""
            QPushButton {
                font-weight: bold; 
                padding: 14px; 
                font-size: 14px;
            }
        """)
        self.btn_apply.setEnabled(False)   # Deshabilitado hasta que se elija un modo
        layout.addWidget(self.btn_apply)

        # Conexiones
        self.btn_integrated.clicked.connect(lambda: self.select_mode("integrated"))
        self.btn_hybrid.clicked.connect(lambda: self.select_mode("hybrid"))
        self.btn_nvidia.clicked.connect(lambda: self.select_mode("nvidia"))
        self.btn_apply.clicked.connect(self.apply_changes)

    def create_tray_icon(self):
        self.tray = QSystemTrayIcon(self)
        self.tray.setToolTip("EnvyControl GUI")
        # Puedes poner un icono real después: self.tray.setIcon(QIcon("icon.png"))

        menu = QMenu()
        show_action = QAction("Mostrar ventana", self)
        quit_action = QAction("Salir", self)
        
        show_action.triggered.connect(self.showNormal)
        quit_action.triggered.connect(QApplication.quit)
        
        menu.addAction(show_action)
        menu.addSeparator()
        menu.addAction(quit_action)
        
        self.tray.setContextMenu(menu)
        self.tray.show()

    def select_mode(self, mode):
        self.selected_mode = mode
        self.status_label.setText(f"Modo seleccionado: <b style='color:#4CAF50'>{mode.upper()}</b>")
        self.btn_apply.setEnabled(True)

    def apply_changes(self):
        if not self.selected_mode:
            QMessageBox.warning(self, "Error", "Por favor selecciona un modo primero.")
            return

        mode = self.selected_mode
        cmd = ["envycontrol", "-s", mode]

        # Opciones avanzadas
        if self.chk_rtd3.isChecked() and mode == "hybrid":
            cmd.append("--rtd3")
        if self.chk_force_comp.isChecked() and mode == "nvidia":
            cmd.append("--force-comp")
        if self.chk_coolbits.isChecked() and mode == "nvidia":
            cmd.extend(["--coolbits", "24"])

        confirm_text = f"¿Cambiar a modo <b>{mode.upper()}</b> y reiniciar el sistema ahora?\n\nEsta acción reiniciará tu equipo automáticamente."
        
        reply = QMessageBox.question(self, "Confirmar cambio", 
                                    confirm_text,
                                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                                    QMessageBox.StandardButton.No)

        if reply != QMessageBox.StandardButton.Yes:
            return

        # Ejecutar con pkexec
        full_cmd = ["pkexec"] + cmd

        try:
            self.process = QProcess(self)
            self.process.finished.connect(self.on_process_finished)
            self.process.errorOccurred.connect(self.on_process_error)
            
            self.process.start(full_cmd[0], full_cmd[1:])
            
            # Pequeño delay para que pkexec muestre el diálogo de contraseña
            QTimer.singleShot(500, lambda: None)

        except Exception as e:
            QMessageBox.critical(self, "Error", f"No se pudo iniciar el proceso:\n{str(e)}")

    def on_process_finished(self, exit_code, exit_status):
        if exit_code == 0:
            # Éxito → reiniciar
            QMessageBox.information(self, "Éxito", 
                                  "El modo se cambió correctamente.\nEl sistema se reiniciará en 3 segundos...")
            QTimer.singleShot(3000, lambda: subprocess.run(["reboot"]))
        else:
            QMessageBox.warning(self, "Error", 
                               f"El comando falló con código {exit_code}.\nRevisa la consola o los logs.")

    def on_process_error(self, error):
        error_msg = {
            QProcess.ProcessError.FailedToStart: "No se pudo iniciar pkexec o envycontrol.",
            QProcess.ProcessError.Crashed: "El proceso se cerró inesperadamente.",
            QProcess.ProcessError.Timedout: "Tiempo de espera agotado.",
        }.get(error, "Error desconocido en el proceso.")
        
        QMessageBox.critical(self, "Error de proceso", error_msg)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")  # Mejor apariencia en la mayoría de entornos
    window = EnvyControlGUI()
    window.show()
    sys.exit(app.exec())

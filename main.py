import os
import sys
from typing import Optional

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (
    QBrush,
    QColor,
    QImage,
    QImageReader,
    QImageWriter,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
)
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QGraphicsObject,
    QGraphicsPixmapItem,
    QGraphicsScene,
    QGraphicsView,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)


def _clamp(value: float, min_value: float, max_value: float) -> float:
    if value < min_value:
        return min_value
    if value > max_value:
        return max_value
    return value


class CropItem(QGraphicsObject):
    def __init__(self, image_rect: QRectF, side: float) -> None:
        super().__init__()
        self._image_rect = QRectF(image_rect)
        self._side = float(side)
        self._handle_size = 12.0
        self._min_side = 40.0

        self._mode: Optional[str] = None  # "move" | "resize"
        self._corner: Optional[str] = None  # "tl" | "tr" | "bl" | "br"
        self._press_scene_pos = QPointF()
        self._press_item_pos = QPointF()
        self._anchor_scene = QPointF()

        self.setAcceptedMouseButtons(Qt.LeftButton)
        self.setAcceptHoverEvents(True)
        self.setZValue(10)

    @property
    def side(self) -> float:
        return self._side

    def boundingRect(self) -> QRectF:
        half = self._handle_size / 2
        return QRectF(-half, -half, self._side + 2 * half, self._side + 2 * half)

    def paint(self, painter: QPainter, option, widget=None) -> None:  # noqa: ANN001
        painter.setRenderHint(QPainter.Antialiasing, True)

        square = QRectF(0, 0, self._side, self._side)
        circle = QRectF(0, 0, self._side, self._side)

        painter.setBrush(Qt.NoBrush)
        painter.setPen(QPen(QColor(46, 204, 113), 2))
        painter.drawRect(square)

        painter.setPen(QPen(QColor(52, 152, 219), 2))
        painter.drawEllipse(circle)

        painter.setPen(QPen(QColor(20, 20, 20), 1))
        painter.setBrush(QBrush(QColor(255, 255, 255)))
        for rect in self._handle_rects().values():
            painter.drawRect(rect)

    def _handle_rects(self) -> dict[str, QRectF]:
        half = self._handle_size / 2
        points = {
            "tl": QPointF(0, 0),
            "tr": QPointF(self._side, 0),
            "bl": QPointF(0, self._side),
            "br": QPointF(self._side, self._side),
        }
        return {
            corner: QRectF(p.x() - half, p.y() - half, self._handle_size, self._handle_size)
            for corner, p in points.items()
        }

    def _corner_at(self, pos: QPointF) -> Optional[str]:
        for corner, rect in self._handle_rects().items():
            if rect.contains(pos):
                return corner
        return None

    def hoverMoveEvent(self, event) -> None:  # noqa: ANN001
        corner = self._corner_at(event.pos())
        if corner in ("tl", "br"):
            self.setCursor(Qt.SizeFDiagCursor)
        elif corner in ("tr", "bl"):
            self.setCursor(Qt.SizeBDiagCursor)
        elif QRectF(0, 0, self._side, self._side).contains(event.pos()):
            self.setCursor(Qt.SizeAllCursor)
        else:
            self.setCursor(Qt.ArrowCursor)

    def mousePressEvent(self, event) -> None:  # noqa: ANN001
        corner = self._corner_at(event.pos())
        if corner is not None:
            self._mode = "resize"
            self._corner = corner
            self._anchor_scene = self._corner_anchor_scene(corner)
            event.accept()
            return

        if QRectF(0, 0, self._side, self._side).contains(event.pos()):
            self._mode = "move"
            self._press_scene_pos = event.scenePos()
            self._press_item_pos = self.pos()
            event.accept()
            return

        event.ignore()

    def mouseMoveEvent(self, event) -> None:  # noqa: ANN001
        if self._mode == "move":
            delta = event.scenePos() - self._press_scene_pos
            self._move_to(self._press_item_pos + delta)
            event.accept()
            return

        if self._mode == "resize" and self._corner is not None:
            self._resize_to(event.scenePos())
            event.accept()
            return

        event.ignore()

    def mouseReleaseEvent(self, event) -> None:  # noqa: ANN001
        self._mode = None
        self._corner = None
        event.accept()

    def _corner_anchor_scene(self, corner: str) -> QPointF:
        if corner == "tl":
            return self.mapToScene(QPointF(self._side, self._side))
        if corner == "tr":
            return self.mapToScene(QPointF(0, self._side))
        if corner == "bl":
            return self.mapToScene(QPointF(self._side, 0))
        return self.mapToScene(QPointF(0, 0))

    def _move_to(self, scene_pos: QPointF) -> None:
        left = self._image_rect.left()
        top = self._image_rect.top()
        right = self._image_rect.right()
        bottom = self._image_rect.bottom()

        x = _clamp(scene_pos.x(), left, right - self._side)
        y = _clamp(scene_pos.y(), top, bottom - self._side)
        self.setPos(QPointF(x, y))

    def _resize_to(self, mouse_scene: QPointF) -> None:
        image_left = self._image_rect.left()
        image_top = self._image_rect.top()
        image_right = self._image_rect.right()
        image_bottom = self._image_rect.bottom()

        anchor = self._anchor_scene
        corner = self._corner
        if corner is None:
            return

        if corner == "br":
            candidate = max(mouse_scene.x() - anchor.x(), mouse_scene.y() - anchor.y())
            max_side = min(image_right - anchor.x(), image_bottom - anchor.y())
            new_pos = QPointF(anchor.x(), anchor.y())
        elif corner == "tl":
            candidate = max(anchor.x() - mouse_scene.x(), anchor.y() - mouse_scene.y())
            max_side = min(anchor.x() - image_left, anchor.y() - image_top)
            new_pos = QPointF(anchor.x() - candidate, anchor.y() - candidate)
        elif corner == "tr":
            candidate = max(mouse_scene.x() - anchor.x(), anchor.y() - mouse_scene.y())
            max_side = min(image_right - anchor.x(), anchor.y() - image_top)
            new_pos = QPointF(anchor.x(), anchor.y() - candidate)
        else:  # "bl"
            candidate = max(anchor.x() - mouse_scene.x(), mouse_scene.y() - anchor.y())
            max_side = min(anchor.x() - image_left, image_bottom - anchor.y())
            new_pos = QPointF(anchor.x() - candidate, anchor.y())

        if max_side <= 1:
            return

        effective_min = min(self._min_side, max_side)
        side = _clamp(candidate, effective_min, max_side)

        if corner == "tl":
            new_pos = QPointF(anchor.x() - side, anchor.y() - side)
        elif corner == "tr":
            new_pos = QPointF(anchor.x(), anchor.y() - side)
        elif corner == "bl":
            new_pos = QPointF(anchor.x() - side, anchor.y())

        self.prepareGeometryChange()
        self._side = float(side)
        self.setPos(new_pos)
        self.update()


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("静态勋章制作")

        self._image_path: Optional[str] = None
        self._image: Optional[QImage] = None
        self._image_rect: Optional[QRectF] = None
        self._crop_item: Optional[CropItem] = None

        self._scene = QGraphicsScene(self)
        self._view = QGraphicsView(self._scene)
        self._view.setRenderHint(QPainter.Antialiasing, True)
        self._view.setRenderHint(QPainter.SmoothPixmapTransform, True)

        self._pixmap_item = QGraphicsPixmapItem()
        self._scene.addItem(self._pixmap_item)

        self._image_path_label = QLabel("未选择图片")
        self._image_path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)

        self._btn_load = QPushButton("添加图片")
        self._btn_load.clicked.connect(self._on_load_image)

        self._save_dir_edit = QLineEdit()
        self._save_dir_edit.setPlaceholderText("保存目录（默认与原图片相同）")

        self._btn_save_dir = QPushButton("保存目录")
        self._btn_save_dir.clicked.connect(self._on_choose_save_dir)

        self._btn_run = QPushButton("运行")
        self._btn_run.clicked.connect(self._on_run)
        self._btn_run.setEnabled(False)

        top_row = QHBoxLayout()
        top_row.addWidget(self._btn_load)
        top_row.addWidget(self._image_path_label, 1)

        save_row = QHBoxLayout()
        save_row.addWidget(self._btn_save_dir)
        save_row.addWidget(self._save_dir_edit, 1)

        layout = QVBoxLayout()
        layout.addLayout(top_row)
        layout.addLayout(save_row)
        layout.addWidget(self._btn_run)
        layout.addWidget(self._view, 1)

        root = QWidget()
        root.setLayout(layout)
        self.setCentralWidget(root)

    def _set_current_image(self, image: QImage, image_path: str) -> None:
        self._image_path = os.path.abspath(image_path)
        self._image = image
        self._image_rect = QRectF(0, 0, image.width(), image.height())

        self._pixmap_item.setPixmap(QPixmap.fromImage(image))
        self._pixmap_item.setOffset(0, 0)
        self._scene.setSceneRect(self._image_rect)
        self._view.fitInView(self._image_rect, Qt.KeepAspectRatio)

        if self._crop_item is not None:
            self._scene.removeItem(self._crop_item)
            self._crop_item = None

        side = float(image.height())
        if side > image.width():
            side = float(image.width())
        x = (image.width() - side) / 2
        y = (image.height() - side) / 2
        self._crop_item = CropItem(self._image_rect, side)
        self._crop_item.setPos(x, y)
        self._scene.addItem(self._crop_item)

        self._image_path_label.setText(self._image_path)
        self._save_dir_edit.setText(os.path.dirname(self._image_path))
        self._btn_run.setEnabled(True)

    def resizeEvent(self, event) -> None:
        super().resizeEvent(event)
        if self._image_rect is not None:
            self._view.fitInView(self._image_rect, Qt.KeepAspectRatio)

    def _on_load_image(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择图片",
            "",
            "Images (*.png *.jpg *.jpeg *.bmp *.webp *.tif *.tiff);;All Files (*)",
        )
        if not path:
            return

        reader = QImageReader(path)
        reader.setAutoTransform(True)
        image = reader.read()
        if image.isNull():
            QMessageBox.critical(self, "错误", f"无法读取图片：{reader.errorString()}")
            return

        self._set_current_image(image, path)

    def _on_choose_save_dir(self) -> None:
        initial = self._save_dir_edit.text().strip() or os.getcwd()
        directory = QFileDialog.getExistingDirectory(self, "选择保存目录", initial)
        if directory:
            self._save_dir_edit.setText(directory)

    def _on_run(self) -> None:
        if self._image is None or self._image_path is None or self._crop_item is None:
            QMessageBox.warning(self, "提示", "请先添加图片。")
            return

        save_dir = self._save_dir_edit.text().strip() or os.path.dirname(self._image_path)
        if not os.path.isdir(save_dir):
            QMessageBox.critical(self, "错误", "保存目录不存在，请重新选择。")
            return

        formats = {bytes(f).decode("ascii", "ignore").lower() for f in QImageWriter.supportedImageFormats()}
        if "webp" not in formats:
            QMessageBox.critical(self, "错误", "当前环境不支持 WebP 导出（缺少 Qt WebP 插件）。")
            return

        img_w = self._image.width()
        img_h = self._image.height()
        side = int(round(self._crop_item.side))
        side = max(1, min(side, img_w, img_h))
        x = int(round(self._crop_item.pos().x()))
        y = int(round(self._crop_item.pos().y()))
        x = max(0, min(x, img_w - side))
        y = max(0, min(y, img_h - side))

        square = self._image.copy(x, y, side, side).convertToFormat(QImage.Format_ARGB32)
        out = QImage(side, side, QImage.Format_ARGB32)
        out.fill(Qt.transparent)

        painter = QPainter(out)
        painter.setRenderHint(QPainter.Antialiasing, True)
        clip = QPainterPath()
        clip.addEllipse(0, 0, side, side)
        painter.setClipPath(clip)
        painter.drawImage(0, 0, square)
        painter.end()

        base = os.path.splitext(os.path.basename(self._image_path))[0]
        out_path = os.path.join(save_dir, f"{base}.webp")
        if os.path.exists(out_path):
            i = 1
            while True:
                candidate = os.path.join(save_dir, f"{base}_{i}.webp")
                if not os.path.exists(candidate):
                    out_path = candidate
                    break
                i += 1

        if not out.save(out_path, "WEBP", 90):
            QMessageBox.critical(self, "错误", "导出失败。")
            return

        self._set_current_image(out, out_path)
        QMessageBox.information(self, "完成", f"已生成并显示：\n{out_path}")


def main() -> int:
    app = QApplication(sys.argv)
    window = MainWindow()
    window.resize(1000, 700)
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

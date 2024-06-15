import cv2
import numpy as np
import time
import serial


def model():
    return cv2.dnn.readNetFromCaffe('model/deploy.prototxt', 'model/res10_300x300_ssd_iter_140000_fp16.caffemodel')


def capture_camera():
    cap = cv2.VideoCapture(0)
    net = model()

    if not cap.isOpened():
        print("Error: Could not open video stream.")
        return

    person_detected = False
    last_out_of_frame_time = None
    last_in_frame = None
    previous_pos = None
    last_movement = None
    last_check_time = time.time()

    try:
        ser = serial.Serial('COM3', 9600)
    except serial.SerialException as e:
        print(f"Error opening serial port: {e}")
        return

    while True:
        # Capture frame-by-frame
        ret, frame = cap.read()

        if not ret:
            print("Error: Could not read frame.")
            break

        (h, w) = frame.shape[:2]
        center_x = w // 2
        center_y = h // 2
        blob = cv2.dnn.blobFromImage(cv2.resize(
            frame, (300, 300)), 1.0, (300, 300), (104.0, 177.0, 123.0))

        net.setInput(blob)
        detections = net.forward()
        current_person_detected = False
        current_pos = None

        for i in range(detections.shape[2]):
            confidence = detections[0, 0, i, 2]

            # Filter out weak detections
            if confidence > 0.5:
                current_person_detected = True
                box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
                (startX, startY, endX, endY) = box.astype("int")
                current_pos = ((startX + endX) / 2, (startY + endY) / 2)

                # Draw the bounding box around the detected object
                label = f"Human Detected: {confidence * 100:.2f}%"
                cv2.rectangle(frame, (startX, startY),
                              (endX, endY), (0, 255, 0), 2)
                y = startY - 10 if startY - 10 > 10 else startY + 10
                cv2.putText(frame, label, (startX, y),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 0), 2)

        current_time = time.time()

        if current_person_detected:
            if last_in_frame is None:
                last_in_frame = current_time
            elif not person_detected and (current_time - last_in_frame) > 2:
                print("Human detected")
                person_detected = True
                last_out_of_frame_time = None
                last_in_frame = None
                ser.write(b'E')
                print("Entry buzzer triggered")
                time.sleep(0.5)

            if current_pos is not None and previous_pos != current_pos and (current_time - last_check_time) > 5:
                x, y = current_pos
                if abs(x - center_x) > w // 10 or abs(y - center_y) > h // 10:
                    new_movement = ""
                    if x < center_x:
                        new_movement += "Move right to center the person. "
                    elif x > center_x:
                        new_movement += "Move left to center the person. "
                    # if y < center_y:
                    #     new_movement += "Move down to center the person. "
                    # elif y > center_y:
                    #     new_movement += "Move up to center the person."

                    if new_movement != last_movement:
                        print(new_movement)
                        last_movement = new_movement
                    last_check_time = current_time  # Update the last check time
                else:
                    if last_movement != "person centered":
                        print("person centered")
                        last_movement = "person centered"
            previous_pos = current_pos
        else:
            if person_detected and last_out_of_frame_time is None:
                last_out_of_frame_time = current_time
            elif last_out_of_frame_time is not None and (current_time - last_out_of_frame_time) > 4:
                if previous_pos:
                    prev_x, prev_y = previous_pos
                    directions = []
                    horizontal_direction = ""
                    vertical_direction = ""
                    if prev_x < w / 3:
                        horizontal_direction = "left"
                        directions.append("left")
                    elif prev_x > 2 * w / 3:
                        horizontal_direction = "right"
                        directions.append("right")
                    else:
                        horizontal_direction = 'no horizontal movement'

                    if prev_y < h / 3:
                        vertical_direction = "down"
                        directions.append("down")
                    elif prev_y > 2 * h / 3:
                        vertical_direction = "up"
                        directions.append("up")
                    else:
                        vertical_direction = "no vertical movement"

                    print(
                        f"Human out of frame, moved to the {horizontal_direction} and {vertical_direction}")
                person_detected = False
                last_out_of_frame_time = None
                last_in_frame = None
                last_movement = None

        cv2.imshow('Frame', frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    ser.close()
    cap.release()
    cv2.destroyAllWindows()


capture_camera()

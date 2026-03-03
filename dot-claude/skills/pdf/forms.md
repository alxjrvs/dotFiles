**CRITICAL: You MUST complete these steps in order. Do not skip ahead to writing code.**

If you need to fill out a PDF form, first check to see if the PDF has fillable form fields. Run this script from this file's directory:
 `python scripts/check_fillable_fields <file.pdf>`, and depending on the result go to either the "Fillable fields" or "Non-fillable fields" and follow those instructions.

# Fillable fields
If the PDF has fillable form fields:
- Run this script from this file's directory: `python scripts/extract_form_field_info.py <input.pdf> <field_info.json>`. It will create a JSON file with a list of fields in this format:
```
[
  {
    "field_id": (unique ID for the field),
    "page": (page number, 1-based),
    "rect": ([left, bottom, right, top] bounding box in PDF coordinates, y=0 is the bottom of the page),
    "type": ("text", "checkbox", "radio_group", or "choice"),
  },
  // Checkboxes have "checked_value" and "unchecked_value" properties:
  {
    "field_id": (unique ID for the field),
    "page": (page number, 1-based),
    "type": "checkbox",
    "checked_value": (Set the field to this value to check the checkbox),
    "unchecked_value": (Set the field to this value to uncheck the checkbox),
  },
  // Radio groups have a "radio_options" list with the possible choices.
  {
    "field_id": (unique ID for the field),
    "page": (page number, 1-based),
    "type": "radio_group",
    "radio_options": [
      {
        "value": (set the field to this value to select this radio option),
        "rect": (bounding box for the radio button for this option)
      },
      // Other radio options
    ]
  },
  // Multiple choice fields have a "choice_options" list with the possible choices:
  {
    "field_id": (unique ID for the field),
    "page": (page number, 1-based),
    "type": "choice",
    "choice_options": [
      {
        "value": (set the field to this value to select this option),
        "text": (display text of the option)
      },
      // Other choice options
    ],
  }
]
```
- Convert the PDF to PNGs (one image for each page) with this script (run from this file's directory):
`python scripts/convert_pdf_to_images.py <file.pdf> <output_directory>`
Then analyze the images to determine the purpose of each form field (make sure to convert the bounding box PDF coordinates to image coordinates).
- Create a `field_values.json` file in this format with the values to be entered for each field:
```
[
  {
    "field_id": "last_name", // Must match the field_id from `extract_form_field_info.py`
    "description": "The user's last name",
    "page": 1, // Must match the "page" value in field_info.json
    "value": "Simpson"
  },
  {
    "field_id": "Checkbox12",
    "description": "Checkbox to be checked if the user is 18 or over",
    "page": 1,
    "value": "/On" // If this is a checkbox, use its "checked_value" value to check it. If it's a radio button group, use one of the "value" values in "radio_options".
  },
  // more fields
]
```
- Run the `fill_fillable_fields.py` script from this file's directory to create a filled-in PDF:
`python scripts/fill_fillable_fields.py <input pdf> <field_values.json> <output pdf>`
This script will verify that the field IDs and values you provide are valid; if it prints error messages, correct the appropriate fields and try again.

# Non-fillable fields
If the PDF doesn't have fillable form fields, you'll add text annotations. First try to extract coordinates from the PDF structure (more accurate), then fall back to visual estimation if needed.

## Step 1: Try Structure Extraction First

Run this script to extract text labels, lines, and checkboxes with their exact PDF coordinates:
`python scripts/extract_form_structure.py <input.pdf> form_structure.json`

This creates a JSON file containing:
- **labels**: Every text element with exact coordinates (x0, top, x1, bottom in PDF points)
- **lines**: Horizontal lines that define row boundaries
- **checkboxes**: Small square rectangles that are checkboxes (with center coordinates)
- **row_boundaries**: Row top/bottom positions calculated from horizontal lines

**Check the results**: If `form_structure.json` has meaningful labels (text elements that correspond to form fields), use **Approach A: Structure-Based Coordinates**. If the PDF is scanned/image-based and has few or no labels, use **Approach B: Visual Estimation**.

---

## Approach A: Structure-Based Coordinates (Preferred)

Use this when `extract_form_structure.py` found text labels in the PDF.

### A.1: Analyze the Structure

Read form_structure.json and identify:

1. **Label groups**: Adjacent text elements that form a single label (e.g., "Last" + "Name")
2. **Row structure**: Labels with similar `top` values are in the same row
3. **Field columns**: Entry areas start after label ends (x0 = label.x1 + gap)
4. **Checkboxes**: Use the checkbox coordinates directly from the structure

**Coordinate system**: PDF coordinates where y=0 is at TOP of page, y increases downward.

### A.2: Create fields.json with PDF Coordinates

For each field, calculate entry coordinates from the extracted structure:

**Text fields:**
- entry x0 = label x1 + 5 (small gap after label)
- entry x1 = next label's x0, or row boundary
- entry top = same as label top
- entry bottom = row boundary line below, or label bottom + row_height

**Checkboxes:**
- Use the checkbox rectangle coordinates directly from form_structure.json
- entry_bounding_box = [checkbox.x0, checkbox.top, checkbox.x1, checkbox.bottom]

Create fields.json using `pdf_width` and `pdf_height` (signals PDF coordinates):
```json
{
  "pages": [
    {"page_number": 1, "pdf_width": 612, "pdf_height": 792}
  ],
  "form_fields": [
    {
      "page_number": 1,
      "description": "Last name entry field",
      "field_label": "Last Name",
      "label_bounding_box": [43, 63, 87, 73],
      "entry_bounding_box": [92, 63, 260, 79],
      "entry_text": {"text": "Smith", "font_size": 10}
    }
  ]
}
```

### A.3: Validate Bounding Boxes

Before filling, check your bounding boxes for errors:
`python scripts/check_bounding_boxes.py fields.json`

---

## Approach B: Visual Estimation (Fallback)

Use this when the PDF is scanned/image-based and structure extraction found no usable text labels.

### B.1: Convert PDF to Images

`python scripts/convert_pdf_to_images.py <input.pdf> <images_dir/>`

### B.2: Initial Field Identification

Examine each page image to identify form sections and get rough estimates of field locations.

### B.3: Zoom Refinement (CRITICAL for accuracy)

For each field, crop a region around the estimated position to refine coordinates precisely.

```bash
magick <page_image> -crop <width>x<height>+<x>+<y> +repage <crop_output.png>
```

### B.4: Create fields.json with Refined Coordinates

Use `image_width` and `image_height` (signals image coordinates).

### B.5: Validate Bounding Boxes

`python scripts/check_bounding_boxes.py fields.json`

---

## Step 2: Fill the Form

`python scripts/fill_pdf_form_with_annotations.py <input.pdf> fields.json <output.pdf>`

## Step 3: Verify Output

`python scripts/convert_pdf_to_images.py <output.pdf> <verify_images/>`

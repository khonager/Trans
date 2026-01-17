from PIL import Image
import sys

source_path = '/home/jl/.gemini/antigravity/brain/e9c8c5af-2d8f-4621-9411-586509d5dd41/uploaded_image_1768608207270.jpg'
dest_path = '/home/jl/Documents/GitHub/personal/Trans/assets/icon.png'
logo_path = '/home/jl/Documents/GitHub/personal/Trans/assets/logo.png'

try:
    img = Image.open(source_path)
    img.save(dest_path, 'PNG')
    img.save(logo_path, 'PNG')
    print(f"Successfully converted and saved to {dest_path} and {logo_path}")
except Exception as e:
    print(f"Error converting image: {e}")
    sys.exit(1)

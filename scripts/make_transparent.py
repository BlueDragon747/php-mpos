#!/usr/bin/env python3
"""
Script to remove white background from blcv3.png and save as blcv4.png with transparency
"""

import sys
import urllib.request
from PIL import Image
import io

def remove_white_background(image_url, output_path):
    """Download image, remove white background, save as transparent PNG"""
    
    try:
        # Download the image with user-agent header
        print(f"Downloading image from {image_url}...")
        
        # Create request with user-agent to avoid 403
        req = urllib.request.Request(
            image_url,
            headers={
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
        )
        
        response = urllib.request.urlopen(req)
        image_data = response.read()
        
        # Open the image
        img = Image.open(io.BytesIO(image_data))
        print(f"Image size: {img.size}, Mode: {img.mode}")
        
        # Convert to RGBA if not already
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        # Get the pixel data
        datas = img.getdata()
        
        # Create new pixel data with transparency for white/very light pixels
        newData = []
        threshold = 240  # Consider pixels above this value as "white"
        
        for item in datas:
            # item is (R, G, B, A)
            r, g, b, a = item
            
            # Check if pixel is white or very light (within threshold)
            if r > threshold and g > threshold and b > threshold:
                # Make it fully transparent
                newData.append((255, 255, 255, 0))
            else:
                # Keep the original pixel
                newData.append(item)
        
        # Put the new pixel data back
        img.putdata(newData)
        
        # Save the image
        img.save(output_path, 'PNG')
        print(f"Successfully saved transparent image to {output_path}")
        
        return True
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    image_url = "https://blakecoin.org/wp-content/uploads/2017/blcv3.png"
    output_path = "public/site_assets/mpos/images/blcv4.png"
    
    success = remove_white_background(image_url, output_path)
    sys.exit(0 if success else 1)

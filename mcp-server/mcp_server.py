#!/usr/bin/env python3
"""
MCP Server for Tool Specification Extraction
Uses Ollama (Qwen2.5) to extract tool specs from vendor websites
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx
import json
import math
import os
from typing import Optional, Dict, Any, List
import re
import base64
from urllib.parse import urljoin, urlparse
from bs4 import BeautifulSoup

app = FastAPI(title="CribHub Tool Import MCP Server")

# Add CORS middleware to allow PocketBase to call this
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your PocketBase domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")

class ToolImportRequest(BaseModel):
    brand: str
    url: str  # Direct URL to the tool page

class ToolSpecsResponse(BaseModel):
    success: bool
    data: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    source_url: Optional[str] = None

class PageUrlRequest(BaseModel):
    url: str

class PageImagesListResponse(BaseModel):
    success: bool
    images: Optional[List[str]] = None
    error: Optional[str] = None
    source_url: Optional[str] = None

class ImageUrlRequest(BaseModel):
    url: str

class ImageBytesResponse(BaseModel):
    success: bool
    content_base64: Optional[str] = None
    content_type: Optional[str] = None
    error: Optional[str] = None

MAX_FETCH_IMAGE_BYTES = 15 * 1024 * 1024

BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

async def fetch_webpage(url: str) -> str:
    """Fetch webpage content"""
    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.text
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch webpage: {str(e)}")

async def fetch_webpage_browser_like(url: str) -> str:
    """Fetch HTML with a browser User-Agent (better for vendor product pages)."""
    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
            response = await client.get(url, headers=BROWSER_HEADERS)
            response.raise_for_status()
            return response.text
    except httpx.HTTPStatusError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to fetch page ({e.response.status_code}): {url}",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch webpage: {str(e)}")

def extract_deboer_model_from_url(url: str) -> Optional[str]:
    """Extract model number from DeBoer product URLs."""
    match = re.search(r"/products/([^/?#]+)", url)
    return match.group(1) if match else None

def _looks_like_image_url(value: str) -> bool:
    low = value.lower()
    image_exts = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".avif", ".svg")
    if any(low.endswith(ext) for ext in image_exts):
        return True
    return "/image" in low or "/images/" in low or "thumbnail" in low

def _collect_image_urls_from_data(
    node: Any,
    base_url: str,
    out: List[str],
    seen: set,
    max_images: int = 50,
) -> None:
    """Recursively collect likely image URLs from unknown JSON structures."""
    if len(out) >= max_images:
        return
    if isinstance(node, str):
        candidate = node.strip()
        if candidate and _looks_like_image_url(candidate):
            normalized = _normalize_image_url(base_url, candidate)
            if normalized and normalized not in seen:
                seen.add(normalized)
                out.append(normalized)
        return
    if isinstance(node, list):
        for item in node:
            _collect_image_urls_from_data(item, base_url, out, seen, max_images=max_images)
            if len(out) >= max_images:
                return
        return
    if isinstance(node, dict):
        for value in node.values():
            _collect_image_urls_from_data(value, base_url, out, seen, max_images=max_images)
            if len(out) >= max_images:
                return

async def fetch_deboer_product_data(model_number: str) -> Dict[str, Any]:
    """Fetch DeBoer product payload from API and return nested product data."""
    api_url = f"https://deboertool.com/api/products/{model_number}"
    print(f"🔍 Fetching DeBoer API: {api_url}")

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(api_url)
        response.raise_for_status()
        data = response.json()

    print("✅ Got DeBoer API response")
    product_data = data.get("data", {})
    if not isinstance(product_data, dict):
        raise HTTPException(status_code=500, detail="Unexpected DeBoer API response format")
    return product_data

def _normalize_image_url(base_url: str, raw: Optional[str]) -> Optional[str]:
    if not raw or not str(raw).strip():
        return None
    raw = str(raw).strip()
    if raw.startswith("data:") or raw.startswith("javascript:"):
        return None
    # srcset: "https://a.jpg 1x, https://b.jpg 2x" -> first URL
    first = raw.split(",")[0].strip().split()
    candidate = first[0] if first else ""
    if not candidate:
        return None
    try:
        abs_url = urljoin(base_url, candidate)
    except Exception:
        return None
    parsed = urlparse(abs_url)
    if parsed.scheme not in ("http", "https"):
        return None
    low = abs_url.lower()
    if any(x in low for x in ("favicon", "pixel.gif", "spacer.gif", "1x1.", "tracking")):
        return None
    return abs_url

def _image_rank(url: str) -> int:
    """Higher rank means show earlier in picker."""
    low = url.lower()
    score = 0

    # Strong positive signals for product/tool imagery.
    for token, pts in (
        ("product-images", 120),
        ("/product/", 90),
        ("tool", 60),
        ("series", 30),
        ("detail", 20),
        ("dimension", 10),
    ):
        if token in low:
            score += pts

    # Prefer full-size images over thumbnails.
    if "thumb" in low or "thumbnail" in low or "small" in low:
        score -= 40
    if "1024x287" in low or "banner" in low or "hero" in low:
        score -= 80

    # Penalize common non-product assets.
    for token, pts in (
        ("logo", 200),
        ("icon", 120),
        ("sprite", 120),
        ("nav", 80),
        ("header", 70),
        ("footer", 70),
        ("cart", 70),
        ("social", 60),
        ("facebook", 60),
        ("instagram", 60),
        ("linkedin", 60),
    ):
        if token in low:
            score -= pts

    # SVGs are frequently logos/icons on vendor pages.
    if low.endswith(".svg"):
        score -= 120

    return score

def extract_image_urls_from_html(html: str, base_url: str, max_images: int = 50) -> List[str]:
    """Collect likely product/content image URLs (og/twitter first, then <img>, <source>)."""
    soup = BeautifulSoup(html, "html.parser")
    seen: set = set()
    ordered: List[str] = []

    def add(u: Optional[str]) -> None:
        if len(ordered) >= max_images:
            return
        nu = _normalize_image_url(base_url, u)
        if nu and nu not in seen:
            seen.add(nu)
            ordered.append(nu)

    for og_prop in ("og:image", "og:image:url", "og:image:secure_url"):
        for tag in soup.find_all("meta", property=og_prop):
            add(tag.get("content"))

    for tag in soup.find_all("meta"):
        name = (tag.get("name") or "").lower()
        if name in ("twitter:image", "twitter:image:src"):
            add(tag.get("content"))

    for tag in soup.find_all("link", rel=lambda x: x and "image_src" in str(x).lower()):
        add(tag.get("href"))

    for img in soup.find_all("img"):
        add(img.get("src"))
        add(img.get("data-src"))
        add(img.get("data-lazy-src"))
        add(img.get("data-original"))
        ds = img.get("data-srcset")
        if ds:
            add(ds.split(",")[0].strip().split()[0] if ds.strip() else None)
        ss = img.get("srcset")
        if ss:
            add(ss.split(",")[0].strip().split()[0] if ss.strip() else None)

    for src in soup.find_all("source"):
        ss = src.get("srcset")
        if ss:
            add(ss.split(",")[0].strip().split()[0] if ss.strip() else None)

    ranked = sorted(ordered, key=_image_rank, reverse=True)
    return ranked[:max_images]

async def extract_deboer_specs(model_number: str) -> Dict[str, Any]:
    """Extract specs from DeBoer Tool API (direct JSON, no AI needed!)"""
    try:
        # The response has structure: { "data": { "spec": {...} }, "user": {...} }
        # We need to get the product data from inside "data"
        product_data = await fetch_deboer_product_data(model_number)
        
        # DEBUG: Print the structure
        print(f"🔍 DEBUG - Product data keys: {list(product_data.keys())[:10]}")
        
        # Extract spec object from product data
        spec = product_data.get('spec', {})
        
        # Map DeBoer fields to our standard fields
        specs = {
            'diameter_in': None,
            'diameter_mm': None,
            'flutes': None,
            'flute_length': None,
            'overall_length': None,
            'corner_rad': None,
            'shank_diameter': None,
            'neck': None,
            'coating': None,
            'material': None,
        }
        
        # Cutting diameter
        if 'linear:cutting-diameter' in spec:
            specs['diameter_in'] = spec['linear:cutting-diameter'].get('value')
            specs['diameter_mm'] = spec['linear:cutting-diameter'].get('valueMm')
        
        # Flutes
        if 'integer:flutes' in spec:
            specs['flutes'] = spec['integer:flutes'].get('value')
        
        # Flute length (cutting length)
        if 'linear:cutting-length' in spec:
            specs['flute_length'] = spec['linear:cutting-length'].get('value')
        
        # Overall length
        if 'linear:overall-length' in spec:
            specs['overall_length'] = spec['linear:overall-length'].get('value')
        
        # Shank diameter
        if 'linear:shank-diameter' in spec:
            specs['shank_diameter'] = spec['linear:shank-diameter'].get('value')
        
        # Corner radius (DeBoer calls it "radius-size")
        if 'linear:radius-size' in spec:
            specs['corner_rad'] = spec['linear:radius-size'].get('value')
        elif 'linear:corner-radius' in spec:
            specs['corner_rad'] = spec['linear:corner-radius'].get('value')
        
        # Coating (if they have it)
        if 'string:coating' in spec:
            specs['coating'] = spec['string:coating'].get('value')
        
        # Material (if they have it)
        if 'string:material' in spec:
            specs['material'] = spec['string:material'].get('value')
        
        print(f"✅ Extracted {sum(1 for v in specs.values() if v is not None)} fields from DeBoer API")
        return specs
        
    except httpx.HTTPError as e:
        raise HTTPException(status_code=500, detail=f"DeBoer API error: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error parsing DeBoer data: {str(e)}")

def extract_dixi_specs_from_js(html_content: str, sku: str) -> Dict[str, Any]:
    """Extract specs from Dixi's JavaScript JSON object (no AI needed!)"""
    try:
        import json
        import re
        
        print(f"🔍 Searching for JavaScript JSON data for SKU {sku}")
        
        # DEBUG: Check if the variable exists at all
        if 'encodedChildrenTechnicalData' in html_content:
            print(f"✅ Variable name found in HTML")
            # Find where it appears
            pos = html_content.find('encodedChildrenTechnicalData')
            context = html_content[max(0, pos-100):pos+200]
            print(f"📍 Context around variable: {context[:300]}")
        else:
            print(f"❌ Variable 'encodedChildrenTechnicalData' NOT found in HTML")
            # Check for alternative names
            alternatives = ['technical', 'product', 'children', 'variation']
            for alt in alternatives:
                if alt in html_content.lower():
                    count = html_content.lower().count(alt)
                    print(f"   - Found '{alt}' {count} times")
        
        # Find the encodedChildrenTechnicalData JSON object
        # It's in a script tag like: const encodedChildrenTechnicalData = JSON.parse("{...}");
        # Try different patterns
        patterns = [
            r'const encodedChildrenTechnicalData = JSON\.parse\("(.+?)"\);',
            r'const encodedChildrenTechnicalData = JSON\.parse\(\"(.+?)\"\);',
            r'encodedChildrenTechnicalData = JSON\.parse\("(.+?)"\)',
            r'encodedChildrenTechnicalData = JSON\.parse\(\'(.+?)\'\)',
        ]
        
        match = None
        for pattern in patterns:
            match = re.search(pattern, html_content, re.DOTALL)
            if match:
                print(f"✅ Found data with pattern: {pattern[:50]}...")
                break
        
        if not match:
            # Try to find it without regex - just search for the variable name
            start_marker = 'encodedChildrenTechnicalData'
            start_pos = html_content.find(start_marker)
            if start_pos != -1:
                # Find the opening quote after JSON.parse(
                parse_pos = html_content.find('JSON.parse(', start_pos)
                if parse_pos != -1:
                    quote_pos = html_content.find('"', parse_pos)
                    if quote_pos != -1:
                        # Find the closing quote and parenthesis
                        # Look for "); or ");
                        end_marker_1 = '");'
                        end_marker_2 = "\");"
                        end_pos_1 = html_content.find(end_marker_1, quote_pos + 1)
                        end_pos_2 = html_content.find(end_marker_2, quote_pos + 1)
                        end_pos = min([p for p in [end_pos_1, end_pos_2] if p != -1], default=-1)
                        
                        if end_pos != -1:
                            json_str = html_content[quote_pos + 1:end_pos]
                            print(f"✅ Found data manually (length: {len(json_str)} chars)")
                        else:
                            print(f"❌ Could not find end marker")
                            raise HTTPException(
                                status_code=500,
                                detail="Could not find product data in page"
                            )
                    else:
                        print(f"❌ Could not find opening quote")
                        raise HTTPException(
                            status_code=500,
                            detail="Could not find product data in page"
                        )
                else:
                    print(f"❌ Could not find JSON.parse(")
                    raise HTTPException(
                        status_code=500,
                        detail="Could not find product data in page"
                    )
            else:
                print(f"❌ Could not find encodedChildrenTechnicalData in HTML")
                raise HTTPException(
                    status_code=500,
                    detail="Could not find product data in page"
                )
        else:
            json_str = match.group(1)
        # Unescape the JSON string
        json_str = json_str.encode().decode('unicode_escape')
        
        # Parse the JSON
        products_data = json.loads(json_str)
        print(f"✅ Found data for {len(products_data)} products")
        
        # Find the product by matching SKU in the data
        product_id = None
        for pid, pdata in products_data.items():
            # The product data is nested, we need to check all variations
            # Just use the first product for now - we'll need to match by SKU properly
            product_id = pid
            break
        
        if not product_id:
            raise HTTPException(
                status_code=500,
                detail=f"Could not find product data for SKU {sku}"
            )
        
        product = products_data[product_id]
        print(f"📦 Using product ID: {product_id}")
        
        # Map Dixi fields to our standard fields
        specs = {
            'diameter_in': None,
            'diameter_mm': None,
            'flutes': None,
            'flute_length': None,
            'overall_length': None,
            'corner_rad': None,
            'shank_diameter': None,
            'neck': None,
            'coating': None,
            'material': None,
            'thread_size': None,
        }
        
        # Extract diameter (D1) - convert mm to inches
        if 'dixi_variation_d1' in product and 'value' in product['dixi_variation_d1']:
            d1_mm = float(product['dixi_variation_d1']['value'])
            specs['diameter_in'] = round(d1_mm / 25.4, 4)
            specs['diameter_mm'] = d1_mm
        
        # Extract flutes (Z)
        if 'dixi_variation_z' in product and 'value' in product['dixi_variation_z']:
            specs['flutes'] = int(product['dixi_variation_z']['value'])
        
        # Extract flute length (L1) - convert mm to inches
        if 'dixi_variation_l1' in product and 'value' in product['dixi_variation_l1']:
            l1_mm = float(product['dixi_variation_l1']['value'])
            specs['flute_length'] = round(l1_mm / 25.4, 4)
        
        # Extract overall length (L) - convert mm to inches
        if 'dixi_variation_l' in product and 'value' in product['dixi_variation_l']:
            l_mm = float(product['dixi_variation_l']['value'])
            specs['overall_length'] = round(l_mm / 25.4, 4)
        
        # Extract shank diameter (D) - convert mm to inches
        if 'dixi_variation_d' in product and 'value' in product['dixi_variation_d']:
            d_mm = float(product['dixi_variation_d']['value'])
            specs['shank_diameter'] = round(d_mm / 25.4, 4)
        
        # Extract thread size (D nom)
        if 'dixi_variation_d_nom' in product and 'value' in product['dixi_variation_d_nom']:
            d_nom = product['dixi_variation_d_nom']['value']
            # Also get pitch (Pas) and combine them
            if 'dixi_variation_pas' in product and 'value' in product['dixi_variation_pas']:
                pas = product['dixi_variation_pas']['value']
                specs['thread_size'] = f"{d_nom}x{pas}"
            else:
                specs['thread_size'] = d_nom
        
        # Extract coating
        if 'dixi_variation_revetement' in product and 'value' in product['dixi_variation_revetement']:
            coating = product['dixi_variation_revetement']['value']
            # Convert "Sans" to "Uncoated"
            if coating.lower() == 'sans':
                coating = 'Uncoated'
            specs['coating'] = coating
        
        print(f"✅ Extracted {sum(1 for v in specs.values() if v is not None)} fields from Dixi JavaScript")
        return specs
        
    except json.JSONDecodeError as e:
        print(f"❌ JSON parsing error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error parsing Dixi JSON: {str(e)}")
    except Exception as e:
        print(f"❌ Error extracting Dixi data: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error extracting Dixi data: {str(e)}")

async def extract_specs_with_ollama(html_content: str, brand: str) -> Dict[str, Any]:
    """Use Ollama (Qwen2.5) to extract tool specifications from HTML"""
    
    # STEP 1: Clean the HTML using BeautifulSoup
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # Remove unwanted elements that add noise
    for element in soup(['script', 'style', 'nav', 'header', 'footer', 'iframe']):
        element.decompose()
    
    # Get clean text
    clean_text = soup.get_text(separator='\n', strip=True)
    
    print(f"🧹 DEBUG - After BeautifulSoup:")
    print(f"   - Clean text length: {len(clean_text)} chars")
    print(f"   - First 500 chars: {clean_text[:500]}")
    print(f"   - Search for 'Technical data': {'FOUND' if 'technical data' in clean_text.lower() else 'NOT FOUND'}")
    print(f"   - Search for 'Technical': {'FOUND' if 'technical' in clean_text.lower() else 'NOT FOUND'}")
    import sys
    sys.stdout.flush()
    
    # Look for "Tool Dimensions" or similar sections and prioritize that area
    lines = clean_text.split('\n')
    start_index = 0
    keywords_found = []
    for i, line in enumerate(lines):
        if any(keyword in line.lower() for keyword in ['tool dimension', 'technical data', 'product specification', 'specifications', 'dimensions']):
            # Start from a few lines before this heading
            start_index = max(0, i - 2)
            keywords_found.append((i, line.strip()[:100]))  # Store line number and preview
            break
    
    print(f"🔍 DEBUG - Keyword search:")
    print(f"   - Total lines: {len(lines)}")
    print(f"   - Keywords found: {keywords_found if keywords_found else 'NONE'}")
    print(f"   - Start index: {start_index}")
    import sys
    sys.stdout.flush()
    
    # Take content starting from that section (or beginning if not found)
    relevant_text = '\n'.join(lines[start_index:start_index + 150])  # ~150 lines should be enough
    
    # Limit to reasonable size
    if len(relevant_text) > 6000:
        relevant_text = relevant_text[:6000]
    
    # STEP 2: Create clear prompt with examples
    prompt = f"""You are extracting cutting tool specifications from a {brand} webpage.

CRITICAL LABEL MAPPINGS (extract the NUMBER after these labels):
- "Cutter Diameter" or "Flute Diameter" or "D1" or "D 1" → diameter_in (this is the main cutting diameter, often VERY SMALL like 0.0080" or 0.0620")
- "Diameter" → diameter_in (if no "Cutter Diameter" or "Flute Diameter" found)
- "Length of Cut" or "Flute Length" or "Flutes Length" or "L1" or "L 1" → flute_length (this is the cutting length, often small like 0.0240" or 0.0930")
- "Number of Flutes" or "Flutes" or "Z" → flutes
- "Overall Length" or "OAL" or "L" → overall_length
- "Corner Radius" or "Corner Rad" → corner_rad
- "Shank Diameter" or "D h5" or "D h6" → shank_diameter
- "Neck Diameter" or "Neck" or "Overall Reach" → neck (the reach or neck dimension)
- "Coating" or "Revetement" → coating (note: "Sans" means "Uncoated")
- "Material" → material
- "D nom" or "Thread Size" or "Thread Designation" → thread_size (e.g., "M1.20", "M2.0")

CONVERSION EXAMPLES (PAY SPECIAL ATTENTION TO SMALL DECIMALS):
Input: "Cutter Diameter: 0.0080" (.2 mm)"       → diameter_in: 0.0080, diameter_mm: 0.2
Input: "Flute Diameter: 0.1875"                → diameter_in: 0.1875
Input: "Cutter Diameter: 0.0620" (1/16)"       → diameter_in: 0.0620
Input: "Cutter Diameter 0.0620" (1/16)"        → diameter_in: 0.0620
Input: "Cutter Diameter: 1.5 inch"             → diameter_in: 1.5
Input: "Diameter: 1/2""                        → diameter_in: 0.5
Input: "Diameter: 1/16 in"                     → diameter_in: 0.0625
Input: "Diameter: 3/32""                       → diameter_in: 0.09375
Input: "Length of Cut: 0.0240""                → flute_length: 0.0240
Input: "Length of Cut: 0.0930" (3/32)"         → flute_length: 0.0930
Input: "Length of Cut 0.0930" (3/32)"          → flute_length: 0.0930
Input: "Flutes Length: 0.5625"                 → flute_length: 0.5625
Input: "Length of Cut: 0.75"                   → flute_length: 0.75
Input: "Number of Flutes: 8"                   → flutes: 8
Input: "Flutes: 3"                             → flutes: 3
Input: "Overall Length: 1.5000" (1-1/2)"       → overall_length: 1.5
Input: "Overall Length: 2.5000" (2-1/2)"       → overall_length: 2.5
Input: "Overall Length: 24 in"                 → overall_length: 24.0
Input: "Shank Diameter: 0.1250" (1/8)"         → shank_diameter: 0.125
Input: "Overall Reach: 0.1400" (9/64)"        → neck: 0.1400
Input: "Neck Diameter: 0.25"                  → neck: 0.25
Input: "Corner Radius: 0.5""                   → corner_rad: 0.5
Input: "Coating: UN"                           → coating: "UN"
Input: "Coating: Sans"                         → coating: "Uncoated"
Input: "Coating: MAYURA"                       → coating: "MAYURA"
Input: "Material: Carbide"                     → material: "Carbide"
Input: "D nom: M1.20"                          → thread_size: "M1.20"
Input: "D1: 1.0"                               → diameter_in: 0.0394 (if mm context, convert: 1.0 / 25.4)
Input: "L1: 3.6"                               → flute_length: 0.1417 (if mm context, convert: 3.6 / 25.4)
Input: "L: 38.0"                               → overall_length: 1.496 (if mm context, convert: 38.0 / 25.4)
Input: "D h5: 3.0"                             → shank_diameter: 0.1181 (if mm context, convert: 3.0 / 25.4)
Input: "Z: 1"                                  → flutes: 1

IMPORTANT RULES:
1. EXTRACT EXACT DECIMAL VALUES including very small ones like 0.0080, 0.0240, 0.0620, 0.0930
2. The number comes RIGHT AFTER the label, before any parentheses or units
3. Example: "Cutter Diameter: 0.0620" (1/16)" → extract 0.0620, ignore (1/16)
4. Convert standalone fractions to decimals: 1/2=0.5, 1/4=0.25, 3/4=0.75, 1/8=0.125, 1/16=0.0625, 3/32=0.09375
5. If values are in millimeters (mm), convert to inches by dividing by 25.4
6. Remove all units (", in, mm, inch) from numbers but keep the number itself
7. Use null if value not found (not "Not found" or empty string)
8. Return ONLY valid JSON, no explanation

Return JSON with these exact fields:
{{
  "diameter_in": number or null,
  "diameter_mm": number or null,
  "flutes": integer or null,
  "flute_length": number or null,
  "overall_length": number or null,
  "corner_rad": number or null,
  "shank_diameter": number or null,
  "neck": number or null,
  "coating": string or null,
  "material": string or null,
  "thread_size": string or null
}}

Webpage content:
{relevant_text}

JSON response:"""

    print(f"📊 DEBUG - Prompt stats:")
    print(f"   - Relevant text length: {len(relevant_text)} chars")
    print(f"   - Full prompt length: {len(prompt)} chars")
    print(f"   - First 200 chars of relevant text: {relevant_text[:200]}")
    import sys
    sys.stdout.flush()

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                f"{OLLAMA_BASE_URL}/api/generate",
                json={
                    "model": OLLAMA_MODEL,
                    "prompt": prompt,
                    "stream": False,
                    "options": {
                        "temperature": 0.1,  # Low temperature for consistent extraction
                        "top_p": 0.9,
                    }
                }
            )
            response.raise_for_status()
            result = response.json()
            
            print(f"✅ Got response from Ollama")
            print(f"   - Response keys: {list(result.keys())}")
            import sys
            sys.stdout.flush()
            
            # Extract the generated text
            generated_text = result.get("response", "")
            
            # Clean up the response - remove markdown code blocks if present
            cleaned = generated_text.strip()
            cleaned = re.sub(r'^```json\s*', '', cleaned)
            cleaned = re.sub(r'^```\s*', '', cleaned)
            cleaned = re.sub(r'\s*```$', '', cleaned)
            cleaned = cleaned.strip()
            
            # Extract just the JSON object (ignore any text after the closing brace)
            # Find the first { and last } to extract only the JSON
            first_brace = cleaned.find('{')
            if first_brace != -1:
                # Find the matching closing brace
                brace_count = 0
                for i in range(first_brace, len(cleaned)):
                    if cleaned[i] == '{':
                        brace_count += 1
                    elif cleaned[i] == '}':
                        brace_count -= 1
                        if brace_count == 0:
                            # Found the closing brace
                            cleaned = cleaned[first_brace:i+1]
                            break
            
            print(f"🔍 DEBUG - JSON extraction:")
            print(f"   - Cleaned response length: {len(cleaned)} chars")
            print(f"   - First 200 chars: {cleaned[:200]}")
            import sys
            sys.stdout.flush()
            
            # Parse JSON
            try:
                specs = json.loads(cleaned)
                
                # Post-process: ensure numeric types are correct
                numeric_fields = ['diameter_in', 'diameter_mm', 'flute_length', 'overall_length', 
                                'corner_rad', 'shank_diameter', 'neck']
                for field in numeric_fields:
                    if field in specs and specs[field] is not None:
                        try:
                            specs[field] = float(specs[field])
                        except (ValueError, TypeError):
                            specs[field] = None
                
                if 'flutes' in specs and specs['flutes'] is not None:
                    try:
                        specs['flutes'] = int(specs['flutes'])
                    except (ValueError, TypeError):
                        specs['flutes'] = None
                
                return specs
                
            except json.JSONDecodeError as e:
                # Log the error for debugging
                print(f"❌ JSON PARSING ERROR:")
                print(f"   Error: {str(e)}")
                print(f"   Raw LLM response (first 500 chars):")
                print(f"   {cleaned[:500]}")
                print(f"   ---")
                
                # If JSON parsing fails, return error with the raw response for debugging
                raise HTTPException(
                    status_code=500, 
                    detail=f"Failed to parse LLM response as JSON: {str(e)}. Raw response: {cleaned[:200]}"
                )
                
    except httpx.HTTPError as e:
        import sys
        print(f"❌ OLLAMA API ERROR:")
        print(f"   Error: {str(e)}")
        print(f"   Traceback:")
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        sys.stderr.flush()
        raise HTTPException(status_code=500, detail=f"Ollama API error: {str(e)}")
    except Exception as e:
        import sys
        print(f"❌ UNEXPECTED ERROR in extract_specs_with_ollama:")
        print(f"   Error: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        print(f"   Traceback:")
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        sys.stderr.flush()
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "online",
        "service": "CribHub Tool Import MCP Server",
        "ollama_url": OLLAMA_BASE_URL,
        "model": OLLAMA_MODEL
    }

@app.get("/health")
async def health_check():
    """Check if Ollama is accessible"""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{OLLAMA_BASE_URL}/api/tags")
            response.raise_for_status()
            return {"status": "healthy", "ollama": "connected"}
    except Exception as e:
        return {"status": "degraded", "ollama": "disconnected", "error": str(e)}

@app.post("/api/extract-tool-specs", response_model=ToolSpecsResponse)
async def extract_tool_specs(request: ToolImportRequest):
    """
    Extract tool specifications from vendor website
    
    Accepts:
    - brand: Brand name (for logging/context)
    - url: Direct URL to the tool page
    """
    
    url = request.url
    if not url:
        raise HTTPException(
            status_code=400,
            detail="URL is required"
        )
    
    try:
        # Check if this is Dixi - extract from JavaScript JSON
        if 'dixipolytool.ch' in url.lower():
            print(f"🎯 Detected Dixi Polytool - extracting from JavaScript JSON")
            
            # Extract SKU from URL
            # URL format: https://dixipolytool.ch/dixi-1740?sku=985136
            import re
            match = re.search(r'[?&]sku=([^&]+)', url)
            if not match:
                raise HTTPException(
                    status_code=400,
                    detail="Could not extract SKU from Dixi URL"
                )
            
            sku = match.group(1)
            print(f"📦 SKU: {sku}")
            
            # Fetch the page
            print(f"🔍 Fetching URL: {url}")
            html_content = await fetch_webpage(url)
            print(f"✅ Fetched {len(html_content)} characters of HTML")
            
            # Extract specs from JavaScript JSON
            specs = extract_dixi_specs_from_js(html_content, sku)
            
            return ToolSpecsResponse(
                success=True,
                data=specs,
                source_url=url
            )
        
        # Check if this is DeBoer Tool - use their API directly!
        if 'deboertool.com' in url.lower():
            print(f"🎯 Detected DeBoer Tool - using API extraction")
            
            # Extract model number from URL
            # URL format: https://deboertool.com/app/products/110-0156-4AR10
            import re
            match = re.search(r'/products/([^/]+)$', url)
            if not match:
                raise HTTPException(
                    status_code=400,
                    detail="Could not extract model number from DeBoer URL"
                )
            
            model_number = match.group(1)
            print(f"📦 Model number: {model_number}")
            
            # Use DeBoer API (no AI needed!)
            specs = await extract_deboer_specs(model_number)
            
            return ToolSpecsResponse(
                success=True,
                data=specs,
                source_url=url
            )
        
        # For other brands (Harvey Tool, etc) - use HTML + AI extraction
        print(f"🔍 Fetching URL: {url}")
        html_content = await fetch_webpage(url)
        print(f"✅ Fetched {len(html_content)} characters of HTML")
        
        # Extract specs using Ollama
        print(f"🤖 Extracting specs with {OLLAMA_MODEL}...")
        import sys
        sys.stdout.flush()  # Force output before potentially long operation
        specs = await extract_specs_with_ollama(html_content, request.brand)
        print(f"✅ Extraction successful!")
        sys.stdout.flush()
        
        return ToolSpecsResponse(
            success=True,
            data=specs,
            source_url=url
        )
        
    except HTTPException:
        raise
    except Exception as e:
        # Log the full error for debugging
        import traceback
        print(f"❌ ERROR during extraction:")
        print(f"   URL: {url}")
        print(f"   Brand: {request.brand}")
        print(f"   Error: {str(e)}")
        print(f"   Traceback:")
        traceback.print_exc()
        
        return ToolSpecsResponse(
            success=False,
            error=str(e),
            source_url=url if 'url' in locals() else None
        )

@app.post("/api/extract-page-images", response_model=PageImagesListResponse)
async def extract_page_images(request: PageUrlRequest):
    """
    Fetch a page and return absolute image URLs for UI selection (og:image, img tags, etc.).
    """
    url = (request.url or "").strip()
    if not url:
        return PageImagesListResponse(success=False, error="URL is required")
    if not url.lower().startswith(("http://", "https://")):
        return PageImagesListResponse(
            success=False,
            error="URL must start with http:// or https://",
        )
    try:
        print(f"🖼️ Extracting image URLs from: {url}")
        if "deboertool.com" in url.lower():
            model_number = extract_deboer_model_from_url(url)
            if not model_number:
                return PageImagesListResponse(
                    success=False,
                    error="Could not extract model number from DeBoer URL.",
                    source_url=url,
                )
            try:
                product_data = await fetch_deboer_product_data(model_number)
                api_images: List[str] = []
                seen: set = set()
                _collect_image_urls_from_data(
                    product_data,
                    "https://deboertool.com",
                    api_images,
                    seen,
                    max_images=50,
                )
                # Prefer primary/product assets over thumbs and logos.
                api_images = sorted(api_images, key=_image_rank, reverse=True)
                if api_images:
                    print(f"✅ Found {len(api_images)} DeBoer image URL(s) from API")
                    return PageImagesListResponse(
                        success=True,
                        images=api_images,
                        source_url=url,
                    )
                print("⚠️ No DeBoer images found in API payload; falling back to HTML scrape")
            except Exception as e:
                print(f"⚠️ DeBoer API image extraction failed: {e}; falling back to HTML scrape")

        html_content = await fetch_webpage_browser_like(url)
        images = extract_image_urls_from_html(html_content, url)
        if not images:
            return PageImagesListResponse(
                success=False,
                error="No suitable images found on this page.",
                source_url=url,
            )
        print(f"✅ Found {len(images)} image URL(s)")
        return PageImagesListResponse(success=True, images=images, source_url=url)
    except HTTPException as e:
        detail = e.detail
        msg = detail if isinstance(detail, str) else str(detail)
        return PageImagesListResponse(success=False, error=msg, source_url=url)
    except Exception as e:
        return PageImagesListResponse(success=False, error=str(e), source_url=url)

@app.post("/api/fetch-image", response_model=ImageBytesResponse)
async def fetch_image_bytes(request: ImageUrlRequest):
    """
    Download an image server-side (avoids browser CORS when saving in Flutter web).
    """
    url = (request.url or "").strip()
    if not url:
        return ImageBytesResponse(success=False, error="URL is required")
    if not url.lower().startswith(("http://", "https://")):
        return ImageBytesResponse(success=False, error="Invalid image URL")
    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=45.0) as client:
            response = await client.get(url, headers=BROWSER_HEADERS)
            response.raise_for_status()
            body = response.content
            ct = (response.headers.get("content-type") or "").split(";")[0].strip()
        if len(body) > MAX_FETCH_IMAGE_BYTES:
            return ImageBytesResponse(success=False, error="Image is too large (max 15 MB)")
        b64 = base64.b64encode(body).decode("ascii")
        return ImageBytesResponse(success=True, content_base64=b64, content_type=ct or "application/octet-stream")
    except httpx.HTTPStatusError as e:
        return ImageBytesResponse(
            success=False,
            error=f"Could not download image (HTTP {e.response.status_code})",
        )
    except Exception as e:
        return ImageBytesResponse(success=False, error=str(e))


# ---------------------------------------------------------------------------
# Toolpath Engine API (quote CAD Phase B)
# ---------------------------------------------------------------------------

TOOLPATH_API_BASE = os.getenv("TOOLPATH_API_BASE", "https://api.toolpath.com/v1").rstrip("/")
TOOLPATH_API_KEY = (os.getenv("TOOLPATH_API_KEY") or "").strip()
TOOLPATH_MAX_BYTES = 50 * 1024 * 1024
# Pad then round each axis up to the next half-inch (shop plate/bar sizes).
STOCK_PAD_IN = float(os.getenv("TOOLPATH_STOCK_PAD_IN", "0.1"))
STOCK_STEP_IN = float(os.getenv("TOOLPATH_STOCK_STEP_IN", "0.5"))


class ToolpathAnalyzeRequest(BaseModel):
    filename: str
    content_base64: str


class ToolpathAnalyzeResponse(BaseModel):
    success: bool
    data: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class ToolpathStatusResponse(BaseModel):
    configured: bool


def _toolpath_headers() -> Dict[str, str]:
    return {
        "Authorization": f"Bearer {TOOLPATH_API_KEY}",
        "Accept": "application/json",
    }


def _mm_to_in(v: float) -> float:
    return v / 25.4


def _format_inch(v: float) -> str:
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return s


def _ceil_to_step(v: float, step: float) -> float:
    if v <= 0 or step <= 0:
        return 0.0
    # Avoid float noise leaving an exact step just under the next bucket.
    return math.ceil((v - 1e-9) / step) * step


def _stock_suggest_from_bbox_in(
    x: float,
    y: float,
    z: float,
    pad: float,
    step: float = STOCK_STEP_IN,
) -> str:
    """BBox + pad, then round each dim up to `step` inches (default 0.5")."""
    dims = sorted(
        [
            _ceil_to_step(x + pad, step),
            _ceil_to_step(y + pad, step),
            _ceil_to_step(z + pad, step),
        ],
        reverse=True,
    )
    return " x ".join(_format_inch(d) for d in dims if d > 0)


async def _toolpath_wait_for_job(client: httpx.AsyncClient, job_id: str) -> Dict[str, Any]:
    """Wait on SSE GET /v1/jobs/{id}/events until succeeded or failed."""
    url = f"{TOOLPATH_API_BASE}/jobs/{job_id}/events"
    event_name: Optional[str] = None
    data_lines: List[str] = []
    async with client.stream("GET", url, headers=_toolpath_headers(), timeout=None) as resp:
        resp.raise_for_status()
        async for raw in resp.aiter_lines():
            line = raw.rstrip("\r")
            if line.startswith(":"):
                continue
            if line.startswith("event:"):
                event_name = line[6:].strip()
                continue
            if line.startswith("data:"):
                data_lines.append(line[5:].lstrip())
                continue
            if line == "":
                if event_name == "job" and data_lines:
                    payload = json.loads("\n".join(data_lines))
                    status = (payload.get("status") or "").lower()
                    if status in ("succeeded", "failed"):
                        return payload
                event_name = None
                data_lines = []
    raise RuntimeError("Toolpath job stream closed without a final status")


def _summarize_part(part: Dict[str, Any]) -> Dict[str, Any]:
    bbox = part.get("boundingBox") or {}
    lower = bbox.get("lower") or {}
    upper = bbox.get("upper") or {}
    try:
        dx = abs(float(upper.get("x", 0)) - float(lower.get("x", 0)))
        dy = abs(float(upper.get("y", 0)) - float(lower.get("y", 0)))
        dz = abs(float(upper.get("z", 0)) - float(lower.get("z", 0)))
    except (TypeError, ValueError):
        dx = dy = dz = 0.0

    bbox_mm = {"x": dx, "y": dy, "z": dz}
    bbox_in = {
        "x": round(_mm_to_in(dx), 4),
        "y": round(_mm_to_in(dy), 4),
        "z": round(_mm_to_in(dz), 4),
    }

    feature_types: Dict[str, int] = {}
    for feat in part.get("features") or []:
        kind = str(feat.get("featureType") or "unknown").strip() or "unknown"
        feature_types[kind] = feature_types.get(kind, 0) + 1

    return {
        "status": "ok",
        "error": None,
        "toolpath_part_id": part.get("partId"),
        "units": part.get("units") or "millimetres",
        "bbox_mm": bbox_mm,
        "bbox_in": bbox_in,
        "stock_suggest_in": _stock_suggest_from_bbox_in(
            bbox_in["x"], bbox_in["y"], bbox_in["z"], STOCK_PAD_IN
        ),
        "stock_pad_in": STOCK_PAD_IN,
        "stock_step_in": STOCK_STEP_IN,
        "feature_count": len(part.get("features") or []),
        "feature_types": feature_types,
        "setup_count": len(part.get("candidateDirections") or []),
        "kernel_version": part.get("kernelVersion"),
    }


@app.get("/api/toolpath/status", response_model=ToolpathStatusResponse)
async def toolpath_status():
    return ToolpathStatusResponse(configured=bool(TOOLPATH_API_KEY))


@app.post("/api/toolpath/analyze", response_model=ToolpathAnalyzeResponse)
async def toolpath_analyze(request: ToolpathAnalyzeRequest):
    """
    Upload CAD bytes to Toolpath, run DFM analysis, return bbox + feature summary.
    Requires TOOLPATH_API_KEY on the server (never send the key from the browser).
    """
    if not TOOLPATH_API_KEY:
        return ToolpathAnalyzeResponse(
            success=False,
            error="TOOLPATH_API_KEY not configured on MCP server",
        )

    filename = (request.filename or "").strip() or "part.step"
    try:
        raw = base64.b64decode(request.content_base64 or "", validate=False)
    except Exception:
        return ToolpathAnalyzeResponse(success=False, error="Invalid content_base64")
    if not raw:
        return ToolpathAnalyzeResponse(success=False, error="CAD file is empty")
    if len(raw) > TOOLPATH_MAX_BYTES:
        return ToolpathAnalyzeResponse(success=False, error="CAD file must be 50 MB or smaller")

    try:
        timeout = httpx.Timeout(30.0, read=360.0)
        async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
            create = await client.post(
                f"{TOOLPATH_API_BASE}/parts",
                params={"filename": filename},
                headers=_toolpath_headers(),
            )
            if create.status_code >= 400:
                detail = create.text[:500]
                return ToolpathAnalyzeResponse(
                    success=False,
                    error=f"Toolpath create part failed ({create.status_code}): {detail}",
                )
            created = create.json()
            part_id = created.get("partId")
            upload_url = created.get("uploadUrl")
            if not part_id or not upload_url:
                return ToolpathAnalyzeResponse(
                    success=False,
                    error="Toolpath create part returned no partId/uploadUrl",
                )

            # Presigned storage URL — do not send the API key.
            put = await client.put(
                upload_url,
                content=raw,
                headers={"Content-Type": "application/octet-stream"},
            )
            if put.status_code >= 400:
                return ToolpathAnalyzeResponse(
                    success=False,
                    error=f"Toolpath CAD upload failed ({put.status_code}): {put.text[:300]}",
                )

            analyze = await client.patch(
                f"{TOOLPATH_API_BASE}/parts/{part_id}",
                headers=_toolpath_headers(),
            )
            if analyze.status_code not in (200, 202):
                return ToolpathAnalyzeResponse(
                    success=False,
                    error=f"Toolpath analyze failed ({analyze.status_code}): {analyze.text[:500]}",
                )
            job = analyze.json()
            job_id = job.get("jobId")
            if not job_id:
                return ToolpathAnalyzeResponse(
                    success=False,
                    error="Toolpath analyze returned no jobId",
                )

            finished = await _toolpath_wait_for_job(client, job_id)
            if (finished.get("status") or "").lower() != "succeeded":
                err = finished.get("error") or "analysis failed"
                return ToolpathAnalyzeResponse(success=False, error=str(err))

            part_resp = await client.get(
                f"{TOOLPATH_API_BASE}/parts/{part_id}",
                headers=_toolpath_headers(),
            )
            if part_resp.status_code >= 400:
                return ToolpathAnalyzeResponse(
                    success=False,
                    error=f"Toolpath get part failed ({part_resp.status_code}): {part_resp.text[:500]}",
                )
            summary = _summarize_part(part_resp.json())
            return ToolpathAnalyzeResponse(success=True, data=summary)
    except httpx.HTTPStatusError as e:
        return ToolpathAnalyzeResponse(
            success=False,
            error=f"Toolpath HTTP {e.response.status_code}: {e.response.text[:400]}",
        )
    except Exception as e:
        return ToolpathAnalyzeResponse(success=False, error=str(e))


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8001"))
    uvicorn.run(app, host="0.0.0.0", port=port)

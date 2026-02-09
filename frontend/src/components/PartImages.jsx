import { useState, useRef, useEffect, useCallback } from 'react'
import { pb } from '../lib/pocketbase'
import { Button } from './ui/Button'

export function PartImages({ record, collectionName, onUpdate, title = 'About this project' }) {
  const [images, setImages] = useState([])
  const [uploading, setUploading] = useState(false)
  const [hoveredImage, setHoveredImage] = useState(null)
  const fileInputRef = useRef(null)
  const containerRef = useRef(null)

  useEffect(() => {
    // Load images from record
    const imageList = record?.part_images || []
    setImages(Array.isArray(imageList) ? imageList : imageList ? [imageList] : [])
  }, [record])

  const getImageUrl = (filename, useThumb = true) => {
    if (!record?.id || !filename) return null
    if (useThumb) {
      return pb.files.getUrl(record, filename, { thumb: '300x300f' })
    }
    return pb.files.getUrl(record, filename)
  }

  const ensureFileName = async (file) => {
    // Always ensure the file has a valid image mime type
    let mimeType = file.type
    
    // If no mime type or invalid, try to detect from file content or default to image/png
    if (!mimeType || !mimeType.startsWith('image/')) {
      // Try to detect mime type from file content
      const arrayBuffer = await file.arrayBuffer()
      const uint8Array = new Uint8Array(arrayBuffer)
      
      // Check for PNG signature (89 50 4E 47)
      if (uint8Array[0] === 0x89 && uint8Array[1] === 0x50 && uint8Array[2] === 0x4E && uint8Array[3] === 0x47) {
        mimeType = 'image/png'
      }
      // Check for JPEG signature (FF D8 FF)
      else if (uint8Array[0] === 0xFF && uint8Array[1] === 0xD8 && uint8Array[2] === 0xFF) {
        mimeType = 'image/jpeg'
      }
      // Check for GIF signature (47 49 46 38)
      else if (uint8Array[0] === 0x47 && uint8Array[1] === 0x49 && uint8Array[2] === 0x46 && uint8Array[3] === 0x38) {
        mimeType = 'image/gif'
      }
      // Check for WebP signature (RIFF...WEBP)
      else if (uint8Array[0] === 0x52 && uint8Array[1] === 0x49 && uint8Array[2] === 0x46 && uint8Array[3] === 0x46) {
        // Check further for WEBP
        const header = String.fromCharCode(...uint8Array.slice(0, 12))
        if (header.includes('WEBP')) {
          mimeType = 'image/webp'
        } else {
          mimeType = 'image/png' // Default fallback
        }
      }
      else {
        mimeType = 'image/png' // Default fallback
      }
    }
    
    const ext = mimeType.split('/')[1] || 'png'
    const fileName = file.name && file.name.trim() !== '' 
      ? file.name 
      : `image-${Date.now()}.${ext}`
    
    // Create a new Blob with the correct type, then create File from that Blob
    // This ensures the type is properly set
    const blob = new Blob([file], { type: mimeType })
    return new File([blob], fileName, { type: mimeType })
  }

  const handleFileSelect = useCallback(async (files) => {
    if (!files || files.length === 0) return
    if (!record?.id) {
      alert('Please save the record first before uploading images.')
      return
    }

    setUploading(true)
    try {
      // Process files to ensure they have correct mime types (async)
      const fileList = await Promise.all(Array.from(files).map(ensureFileName))
      
      // Log file info for debugging
      fileList.forEach((file, idx) => {
        console.log(`File ${idx + 1}:`, {
          name: file.name,
          type: file.type,
          size: file.size,
        })
      })
      
      // Upload files one at a time using FormData to ensure mime type is sent correctly
      let lastUpdated = null
      for (const file of fileList) {
        console.log('Uploading file:', file.name, 'with type:', file.type)
        
        // Use FormData to ensure the file's mime type is properly sent
        const formData = new FormData()
        formData.append('part_images+', file, file.name)
        
        // Verify FormData entry
        const formDataEntry = formData.get('part_images+')
        console.log('FormData file type:', formDataEntry?.type, 'name:', formDataEntry?.name)
        
        lastUpdated = await pb.collection(collectionName).update(record.id, formData)
      }
      
      const updated = lastUpdated || record
      const imageList = updated.part_images || []
      setImages(Array.isArray(imageList) ? imageList : imageList ? [imageList] : [])
      if (onUpdate) onUpdate(updated)
    } catch (e) {
      console.error('Failed to upload images:', e)
      console.error('Error response:', e?.response)
      console.error('Error response.data:', e?.response?.data)
      console.error('Full error:', JSON.stringify(e?.response, null, 2))
      const errorMsg = e?.response?.data?.message || e?.response?.message || e?.message || 'Failed to upload images. Check the console.'
      alert(errorMsg)
    } finally {
      setUploading(false)
    }
  }, [record?.id, collectionName, onUpdate])

  const handleFileInput = (e) => {
    handleFileSelect(e.target.files)
    e.target.value = '' // Reset input
  }

  const handlePaste = useCallback(async (e) => {
    if (!record?.id) return
    const items = e.clipboardData?.items
    if (!items) return

    const imageFiles = []
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (item.type.startsWith('image/')) {
        const file = item.getAsFile()
        if (file) imageFiles.push(file)
      }
    }

    if (imageFiles.length > 0) {
      e.preventDefault()
      handleFileSelect(imageFiles)
    }
  }, [record?.id, handleFileSelect])

  const handleDelete = async (filename) => {
    if (!record?.id || !confirm('Delete this image?')) return

    try {
      const updated = await pb.collection(collectionName).update(record.id, {
        'part_images-': filename,
      })
      const imageList = updated.part_images || []
      setImages(Array.isArray(imageList) ? imageList : imageList ? [imageList] : [])
      if (onUpdate) onUpdate(updated)
    } catch (e) {
      console.error('Failed to delete image:', e)
      alert('Failed to delete image. Check the console.')
    }
  }

  useEffect(() => {
    const container = containerRef.current
    if (!container || !record?.id) return
    container.addEventListener('paste', handlePaste)
    return () => container.removeEventListener('paste', handlePaste)
  }, [record?.id, handlePaste])

  return (
    <div ref={containerRef} className="space-y-3">
      {title ? (
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold text-gray-700">{title}</h3>
          {record?.id && (
          <div className="flex gap-2">
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              multiple
              className="hidden"
              onChange={handleFileInput}
            />
            <Button
              type="button"
              variant="secondary"
              className="!py-1 !text-xs"
              disabled={uploading}
              onClick={() => fileInputRef.current?.click()}
            >
              {uploading ? 'Uploading…' : '+ Upload images'}
            </Button>
          </div>
          )}
        </div>
      ) : record?.id ? (
        <div className="flex justify-end">
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            multiple
            className="hidden"
            onChange={handleFileInput}
          />
          <Button
            type="button"
            variant="secondary"
            className="!py-1 !text-xs"
            disabled={uploading}
            onClick={() => fileInputRef.current?.click()}
          >
            {uploading ? 'Uploading…' : '+ Upload images'}
          </Button>
        </div>
      ) : null}

      {!record?.id && (
        <p className="text-sm text-gray-500">
          Save this {collectionName === 'quotes' ? 'quote' : 'job'} first to upload images.
        </p>
      )}

      {images.length > 0 && (
        <>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
            {images.map((filename, idx) => {
              const thumbUrl = getImageUrl(filename, true)
              const fullUrl = getImageUrl(filename, false)
              if (!thumbUrl || !fullUrl) return null
              return (
                <div
                  key={idx}
                  className="group relative aspect-square overflow-hidden rounded-lg border border-gray-200 bg-gray-50 cursor-pointer"
                  onMouseEnter={() => setHoveredImage({ url: fullUrl, alt: `Part ${idx + 1}` })}
                  onMouseLeave={() => setHoveredImage(null)}
                >
                  <img
                    src={thumbUrl}
                    alt={`Part ${idx + 1}`}
                    className="h-full w-full object-contain transition-transform group-hover:scale-105"
                  />
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation()
                      handleDelete(filename)
                    }}
                    className="absolute right-1 top-1 rounded bg-red-500 px-2 py-1 text-xs text-white opacity-0 transition-opacity group-hover:opacity-100 hover:bg-red-600 z-10"
                    title="Delete image"
                  >
                    ×
                  </button>
                </div>
              )
            })}
          </div>
          
          {/* Hover popup */}
          {hoveredImage && (
            <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-75 p-4 pointer-events-none">
              <img
                src={hoveredImage.url}
                alt={hoveredImage.alt}
                className="max-h-full max-w-full object-contain"
                style={{ maxHeight: '90vh', maxWidth: '90vw' }}
              />
            </div>
          )}
        </>
      )}

      {images.length === 0 && record?.id && (
        <div className="rounded-lg border-2 border-dashed border-gray-300 p-8 text-center">
          <p className="text-sm text-gray-500">No images yet. Upload or paste images to add them.</p>
        </div>
      )}
    </div>
  )
}

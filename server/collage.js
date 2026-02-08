import express from 'express';

const router = express.Router();

export function registerCollageRoutes(app) {
  app.use('/collage', router);
}

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

router.post('/generate-background', async (req, res) => {
  try {
    const { photos, memories, style } = req.body;

    // Validate input
    if (!photos || !Array.isArray(photos) || photos.length === 0) {
      return res.status(400).json({
        ok: false,
        error: 'Missing or invalid photos array',
      });
    }

    if (!memories || !Array.isArray(memories) || memories.length === 0) {
      return res.status(400).json({
        ok: false,
        error: 'Missing or invalid memories array',
      });
    }

    console.log('[Collage] Generating collage for', photos.length, 'photos and', memories.length, 'memories');

    // 1. Analyze context
    const theme = analyzeTheme(photos, memories);
    const mood = analyzeMood(memories);
    const colors = suggestColorPalette(theme, photos);
    const season = getSeasonFromPhotos(photos);

    // 2. Build DALL-E prompt
    const prompt = buildPrompt(theme, mood, colors, season, style);

    console.log('[Collage] Generating background with prompt:', prompt);

    // 3. Call DALL-E 3 using fetch
    const response = await fetch("https://api.openai.com/v1/images/generations", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "dall-e-3",
        prompt: prompt,
        n: 1,
        size: "1024x1792",
        quality: "standard", // or "hd" for $0.080
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error?.message || 'DALL-E API error');
    }

    const data = await response.json();
    const backgroundUrl = data.data[0].url;

    console.log('[Collage] Background generated successfully');

    // 4. Return result
    res.json({
      ok: true,
      background_url: backgroundUrl,
      theme: theme,
      colors: colors,
      prompt: prompt, // for debugging
    });

  } catch (error) {
    // Fallback to template
    console.error('[Collage] DALL-E error:', error);
    console.error('[Collage] Error details:', {
      message: error.message,
      status: error.status,
      type: error.type,
    });

    // Check if OPENAI_API_KEY is set
    if (!process.env.OPENAI_API_KEY) {
      console.error('[Collage] OPENAI_API_KEY is not set!');
    }

    res.json({
      ok: true,
      fallback: true,
      background_url: '', // Empty URL signals fallback
      template: {
        type: 'gradient',
        colors: ['#FF6B6B', '#4ECDC4', '#45B7D1'],
      },
      theme: 'nature',
      colors: ['#FF6B6B', '#4ECDC4', '#45B7D1'],
      message: 'Using template fallback',
      error: error.message, // Include error message for debugging
    });
  }
});

// Helper functions
function analyzeTheme(photos, memories) {
  // Extract locations from photos
  const locations = (photos || []).map(p => (p.location || '').toLowerCase());

  // Check for beach keywords
  if (locations.some(loc =>
    loc.includes('beach') || loc.includes('ocean') || loc.includes('coast') || loc.includes('sea')
  )) {
    return 'beach';
  }

  // Check for mountain keywords
  if (locations.some(loc =>
    loc.includes('mountain') || loc.includes('peak') || loc.includes('summit') || loc.includes('hiking')
  )) {
    return 'mountain';
  }

  // Check for urban keywords
  if (locations.some(loc =>
    loc.includes('city') || loc.includes('downtown') || loc.includes('urban') || loc.includes('street')
  )) {
    return 'urban';
  }

  // Check memory transcriptions
  const transcriptions = memories.map(m => (m.transcription || '').toLowerCase()).join(' ');
  if (transcriptions.includes('city') || transcriptions.includes('urban') || transcriptions.includes('building')) {
    return 'urban';
  }
  if (transcriptions.includes('beach') || transcriptions.includes('ocean')) {
    return 'beach';
  }
  if (transcriptions.includes('mountain') || transcriptions.includes('hiking')) {
    return 'mountain';
  }

  // Default
  return 'nature';
}

function analyzeMood(memories) {
  const text = (memories || []).map(m => (m.transcription || '').toLowerCase()).join(' ');

  if (text.match(/amazing|incredible|wonderful|happy|fun|exciting|joy/)) {
    return 'joyful';
  }
  if (text.match(/calm|relaxing|peaceful|serene|quiet|tranquil/)) {
    return 'peaceful';
  }
  if (text.match(/adventure|exploring|exciting|thrilling|epic/)) {
    return 'adventurous';
  }
  if (text.match(/remember|memories|miss|back when|nostalgia/)) {
    return 'nostalgic';
  }

  return 'nostalgic';
}

function suggestColorPalette(theme, photos) {
  const palettes = {
    beach: ['#FF6B6B', '#4ECDC4', '#FFE66D'], // Coral, turquoise, sandy beige
    mountain: ['#2D5F3F', '#E67E22', '#3498DB'], // Forest green, autumn orange, sky blue
    urban: ['#2C3E50', '#9B59B6', '#F39C12'], // Deep navy, neon purple, gold
    nature: ['#27AE60', '#F1C40F', '#3498DB'], // Green, yellow, blue
  };

  return palettes[theme] || palettes.nature;
}

function getSeasonFromPhotos(photos) {
  // Use most recent photo's timestamp
  const dates = photos
    .map(p => p.timestamp ? new Date(p.timestamp) : null)
    .filter(d => d && !isNaN(d));

  if (dates.length === 0) return 'summer';

  const latestDate = dates.sort((a, b) => b - a)[0];
  const month = latestDate.getMonth();

  if (month >= 2 && month <= 4) return 'spring';
  if (month >= 5 && month <= 7) return 'summer';
  if (month >= 8 && month <= 10) return 'fall';
  return 'winter';
}

function buildPrompt(theme, mood, colors, season, style) {
  const themeDescriptions = {
    beach: 'ocean-inspired',
    mountain: 'mountain landscape',
    urban: 'urban geometric',
    nature: 'natural landscape',
  };

  const styleDescriptions = {
    scrapbook: 'minimalist',
    magazine: 'clean modern',
    minimal: 'ultra minimal',
  };

  const moodDescriptions = {
    joyful: 'vibrant',
    peaceful: 'serene',
    adventurous: 'dynamic',
    nostalgic: 'warm',
  };

  const colorStr = colors.join(', ');

  return `Minimalist abstract ${themeDescriptions[theme]} background with ${colorStr} color scheme, ${styleDescriptions[style || 'scrapbook']} aesthetic, clean simple design, subtle gradients, no complex textures, no photos, no text, no people, no objects, 1024x1792 portrait orientation, ${moodDescriptions[mood]} mood`;
}

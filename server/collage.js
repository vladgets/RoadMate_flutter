import express from 'express';
import OpenAI from 'openai';

const router = express.Router();

export function registerCollageRoutes(app) {
  app.use('/collage', router);
}

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

router.post('/generate-background', async (req, res) => {
  try {
    const { photos, memories, style } = req.body;

    // 1. Analyze context
    const theme = analyzeTheme(photos, memories);
    const mood = analyzeMood(memories);
    const colors = suggestColorPalette(theme, photos);
    const season = getSeasonFromPhotos(photos);

    // 2. Build DALL-E prompt
    const prompt = buildPrompt(theme, mood, colors, season, style);

    console.log('[Collage] Generating background with prompt:', prompt);

    // 3. Call DALL-E 3
    const response = await openai.images.generate({
      model: "dall-e-3",
      prompt: prompt,
      n: 1,
      size: "1024x1792",
      quality: "standard", // or "hd" for $0.080
    });

    const backgroundUrl = response.data[0].url;

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
    res.json({
      ok: true,
      fallback: true,
      template: {
        type: 'gradient',
        colors: ['#FF6B6B', '#4ECDC4', '#45B7D1'],
      },
      theme: 'nature',
      colors: ['#FF6B6B', '#4ECDC4', '#45B7D1'],
      message: 'Using template fallback',
    });
  }
});

// Helper functions
function analyzeTheme(photos, memories) {
  // Extract locations from photos
  const locations = photos.map(p => (p.location || '').toLowerCase());

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
  const text = memories.map(m => (m.transcription || '').toLowerCase()).join(' ');

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
    urban: 'urban night',
    nature: 'natural landscape',
  };

  const styleDescriptions = {
    scrapbook: 'watercolor',
    magazine: 'modern gradient',
    minimal: 'minimalist geometric',
  };

  const moodDescriptions = {
    joyful: 'vibrant energetic',
    peaceful: 'peaceful serene',
    adventurous: 'adventurous dynamic',
    nostalgic: 'warm nostalgic',
  };

  const colorStr = colors.join(', ');

  return `Abstract ${themeDescriptions[theme]} background with ${colorStr} color scheme, ${styleDescriptions[style || 'scrapbook']} aesthetic, suitable for photo collage overlay, soft gradients and textures, no photos, no text, no people, 1024x1792 portrait orientation, ${moodDescriptions[mood]} atmosphere`;
}

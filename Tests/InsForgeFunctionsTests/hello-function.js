// Hello function for InsForge Functions Tests
// This function is deployed to test the Swift SDK's functions client

module.exports = async function(request) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
  };

  // Handle CORS preflight
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  // Parse request body
  let body = {};
  try {
    const text = await request.text();
    if (text) {
      body = JSON.parse(text);
    }
  } catch (e) {
    // Ignore parse errors, use empty body
  }

  // Generate greeting message
  const name = body.name;
  const message = name ? `Hello, ${name}!` : "Hello, World!";

  return new Response(JSON.stringify({ message }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ detail: 'Method not allowed' });
  }

  try {
    const { name, email, contact, company, message } = req.body || {};

    if (!name || !email || !contact) {
      return res.status(400).json({ detail: 'name, email, and contact are required' });
    }

    const resendApiKey = process.env.RESEND_API_KEY;
    const fromEmail = process.env.FROM_EMAIL || 'noreply@gymopshq.com';
    const toEmail = process.env.CONTACT_TO_EMAIL || 'contact@dertzinfotech.com';

    if (!resendApiKey) {
      return res.status(500).json({ detail: 'Missing RESEND_API_KEY' });
    }

    const safeCompany = company || 'NA';
    const safeMessage = message || 'GymOpsHQ';

    const html = `
      <div style="font-family: Arial, sans-serif; line-height: 1.6;">
        <h2>New GymOpsHQ Signup Request</h2>
        <p><strong>Name:</strong> ${name}</p>
        <p><strong>Email:</strong> ${email}</p>
        <p><strong>Phone:</strong> ${contact}</p>
        <p><strong>Company:</strong> ${safeCompany}</p>
        <p><strong>Message:</strong> ${safeMessage}</p>
      </div>
    `;

    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [toEmail],
        subject: `${name} wants to get in touch with you`,
        html,
      }),
    });

    const data = await response.json();
    if (!response.ok) {
      return res.status(response.status).json({
        detail: 'Email provider request failed',
        provider_response: data,
      });
    }

    return res.status(200).json({ status: 1, message: 'Send request confirm', data });
  } catch (error) {
    return res.status(500).json({ detail: `Unexpected server error: ${error.message}` });
  }
}

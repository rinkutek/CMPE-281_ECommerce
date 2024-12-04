const API_BASE_URL = 'http://127.0.0.1:5002';

// Utility function for authenticated requests
const fetchWithAuth = (url, options = {}) => {
    const token = localStorage.getItem('token');
    return fetch(url, {
        ...options,
        headers: {
            'Authorization': token,
            'Content-Type': 'application/json',
            ...options.headers,
        },
    });
};


// Handle registration form submission
document.getElementById('registerForm').addEventListener('submit', async (e) => {
    e.preventDefault(); // Prevent traditional form submission

    // Capture form inputs
    const username = document.getElementById('username').value;
    const password = document.getElementById('password').value;
    const name = document.getElementById('name').value;
    const email = document.getElementById('email').value;

    try {
        // Make API request to the /api/register endpoint
        const response = await fetch('/api/register', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password, name, email }),
        });

        const data = await response.json();
        if (response.ok) {
            alert(data.message); // Success message
            window.location.href = '/login'; // Redirect to login page
        } else {
            alert(data.error || 'Registration failed'); // Error message
        }
    } catch (error) {
        console.error('Error occurred during registration:', error);
        alert('An unexpected error occurred. Please try again later.');
    }
});


// User Login
document.getElementById('login').addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = document.getElementById('loginUsername').value;
    const password = document.getElementById('loginPassword').value;

    const response = await fetch(`${API_BASE_URL}/api/login`, {
        method: 'POST',
        body: JSON.stringify({ username, password }),
    });
    const data = await response.json();
    alert(data.message);
    if (data.token) localStorage.setItem('token', data.token);
});

// Fetch and Filter Products
document.getElementById('fetchProducts').addEventListener('click', async () => {
    const query = document.getElementById('searchQuery').value;
    const response = await fetch(`${API_BASE_URL}/api/products?query=${query}`);
    const data = await response.json();

    const productsDiv = document.getElementById('products');
    productsDiv.innerHTML = `
        <ul>
            ${data.products.map(product => `<li>${product.name} - $${product.price}</li>`).join('')}
        </ul>
    `;
});

// Add to Cart


// Place Order
document.getElementById('placeOrder').addEventListener('click', async () => {
    const response = await fetchWithAuth(`${API_BASE_URL}/api/order`, { method: 'POST' });
    const data = await response.json();
    alert(data.message);
});

// Make Payment
document.getElementById('makePayment').addEventListener('click', async () => {
    const orderId = '12345'; // Example order ID
    const response = await fetchWithAuth(`${API_BASE_URL}/api/payment`, {
        method: 'POST',
        body: JSON.stringify({ order_id: orderId, amount: 1200 }),
    });
    const data = await response.json();
    alert(data.message);
});

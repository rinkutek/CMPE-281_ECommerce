from flask import Flask, jsonify, request
from flask_cors import CORS
import uuid

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# In-memory databases for demo purposes
users = {}
products = [
    {"id": 1, "name": "Laptop", "price": 1200, "category": "Electronics"},
    {"id": 2, "name": "Smartphone", "price": 800, "category": "Electronics"},
    {"id": 3, "name": "Headphones", "price": 150, "category": "Accessories"}
]
orders = []
cart = {}

# Helper function for authentication
def authenticate_user(token):
    user = next((user for user in users.values() if user['token'] == token), None)
    return user


# User Registration
@app.route('/api/register', methods=['POST'])
def register():
    data = request.json
    username = data.get('username')
    password = data.get('password')
    name = data.get('name', '')
    email = data.get('email', '')

    if not username or not password:
        return jsonify({'error': 'Username and password are required'}), 400

    if username in users:  # Assuming `users` is a dictionary or database
        return jsonify({'error': 'Username already exists'}), 400

    hashed_password = generate_password_hash(password)
    token = str(uuid.uuid4())
    users[username] = {
        'username': username,
        'password': hashed_password,
        'token': token,
        'profile': {'name': name, 'email': email}
    }
    return jsonify({'message': 'Registration successful'})



# User Login
@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    user = users.get(data.get('username'))
    if user and user['password'] == data['password']:
        return jsonify({'message': 'Login successful', 'token': user['token']})
    return jsonify({'error': 'Invalid credentials'}), 401


# Manage Profile
@app.route('/api/profile', methods=['GET', 'PUT'])
def manage_profile():
    token = request.headers.get('Authorization')
    user = authenticate_user(token)
    if not user:
        return jsonify({'error': 'Unauthorized'}), 401
    
    if request.method == 'GET':
        return jsonify({'profile': user['profile']})
    
    if request.method == 'PUT':
        user['profile'].update(request.json)
        return jsonify({'message': 'Profile updated successfully'})


# Product Service - Filter, Sort, and Search
@app.route('/api/products', methods=['GET'])
def get_products():
    query = request.args.get('query', '').lower()
    sort_by = request.args.get('sort_by')
    category = request.args.get('category')
    
    filtered_products = [p for p in products if query in p['name'].lower()]
    if category:
        filtered_products = [p for p in filtered_products if p['category'].lower() == category.lower()]
    
    if sort_by == 'price_asc':
        filtered_products.sort(key=lambda x: x['price'])
    elif sort_by == 'price_desc':
        filtered_products.sort(key=lambda x: x['price'], reverse=True)
    
    return jsonify({"products": filtered_products})


# Shopping Cart - Add and View Items
@app.route('/api/cart', methods=['GET', 'POST'])
def cart_service():
    token = request.headers.get('Authorization')
    user = authenticate_user(token)
    if not user:
        return jsonify({'error': 'Unauthorized'}), 401
    
    user_cart = cart.get(user['username'], [])
    
    if request.method == 'GET':
        return jsonify({'cart': user_cart})
    
    if request.method == 'POST':
        item = request.json.get('item')
        user_cart.append(item)
        cart[user['username']] = user_cart
        return jsonify({'message': 'Item added to cart'})


# Place Order
@app.route('/api/order', methods=['POST'])
def place_order():
    token = request.headers.get('Authorization')
    user = authenticate_user(token)
    if not user:
        return jsonify({'error': 'Unauthorized'}), 401
    
    user_cart = cart.get(user['username'], [])
    if not user_cart:
        return jsonify({'error': 'Cart is empty'}), 400
    
    order_id = str(uuid.uuid4())
    orders.append({'id': order_id, 'user': user['username'], 'items': user_cart})
    cart[user['username']] = []
    return jsonify({'message': 'Order placed successfully', 'order_id': order_id})


# Payment Gateway (Mock)
@app.route('/api/payment', methods=['POST'])
def payment():
    data = request.json
    if not data.get('order_id') or not data.get('amount'):
        return jsonify({'error': 'Invalid payment details'}), 400
    return jsonify({'message': 'Payment processed successfully', 'transaction_id': str(uuid.uuid4())})


if __name__ == '__main__':
    app.run(debug=True)

import 'package:flutter/material.dart';

class NetflixNavbar extends StatefulWidget {
  final String activeCategory;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickLocalFile;
  final VoidCallback onConnectFolder;
  final String? connectedFolderName;

  const NetflixNavbar({
    super.key,
    required this.activeCategory,
    required this.onCategoryChanged,
    required this.onSearchChanged,
    required this.onPickLocalFile,
    required this.onConnectFolder,
    this.connectedFolderName,
  });

  @override
  State<NetflixNavbar> createState() => _NetflixNavbarState();
}

class _NetflixNavbarState extends State<NetflixNavbar> {
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 900;

    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          // Logo Red Style
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LOCAL TV',
                style: TextStyle(
                  color: const Color(0xFFE50914),
                  fontSize: isCompact ? 20 : 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'v2',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: isCompact ? 16 : 32),

          // Categories Links
          _buildNavLink('series', 'Series'),
          const SizedBox(width: 16),
          _buildNavLink('films', 'Films'),
          const SizedBox(width: 16),
          _buildNavLink('local', 'Folder Film Saya'),
          const SizedBox(width: 16),

          // Connect Folder Button
          TextButton.icon(
            onPressed: widget.onConnectFolder,
            icon: const Icon(Icons.folder_special, color: Color(0xFFE50914), size: 16),
            label: Text(
              widget.connectedFolderName != null
                  ? '📁 ${widget.connectedFolderName}'
                  : 'Hubungkan Folder Film',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              backgroundColor: const Color(0xFFE50914).withValues(alpha: 0.15),
              side: const BorderSide(color: Color(0xFFE50914), width: 0.8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Pick Single File
          if (!isCompact)
            TextButton.icon(
              onPressed: widget.onPickLocalFile,
              icon: const Icon(Icons.file_open_outlined, color: Colors.white70, size: 16),
              label: const Text(
                'Buka File',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),

          const Spacer(),

          // Search Field
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: _isSearchOpen ? (isCompact ? 160 : 220) : 38,
            height: 38,
            decoration: BoxDecoration(
              color: _isSearchOpen ? Colors.black87 : Colors.transparent,
              border: Border.all(
                color: _isSearchOpen ? Colors.white54 : Colors.transparent,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.search, color: Colors.white, size: 20),
                    onPressed: () {
                      setState(() {
                        _isSearchOpen = !_isSearchOpen;
                        if (!_isSearchOpen) {
                          _searchController.clear();
                          widget.onSearchChanged('');
                        }
                      });
                    },
                  ),
                ),
                if (_isSearchOpen)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search titles...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.only(right: 8),
                      ),
                      onChanged: widget.onSearchChanged,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Profile Avatar (Netflix style)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              'assets/images/users/1.png',
              width: 30,
              height: 30,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 30,
                height: 30,
                color: const Color(0xFFE50914),
                child: const Icon(Icons.person, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavLink(String id, String label) {
    final bool isActive = widget.activeCategory == id;
    return InkWell(
      onTap: () => widget.onCategoryChanged(id),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white60,
          fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
          fontSize: 14,
        ),
      ),
    );
  }
}

package co.edu.uptc.usuarios.dto;

public class UsuarioDTO {

    private Integer id;
    private String name;
    private String username;
    private String email;
    private String message;
    private String ipAddress;
    private String instanceTag;

    public Integer getId() { 
        return id; 
    }
    public void setId(Integer id) { 
        this.id = id; 
    }
    public String getName() { 
        return name; 
    }
    public void setName(String name) { 
        this.name = name; 
    }
    public String getUsername() { 
        return username; 
    }
    public void setUsername(String username) { 
        this.username = username; 
    }
    public String getEmail() { 
        return email; 
    }
    public void setEmail(String email) { 
        this.email = email; 
    }
    public String getMessage() { 
        return message; 
    }
    public void setMessage(String message) { 
        this.message = message; 
    }
    public String getIpAddress() { 
        return ipAddress; 
    }
    public void setIpAddress(String ipAddress) { 
        this.ipAddress = ipAddress; 
    }
    public String getInstanceTag() {
        return instanceTag;
    }
    public void setInstanceTag(String instanceTag) {
        this.instanceTag = instanceTag;
    }
}

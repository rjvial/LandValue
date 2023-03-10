function calculaAnguloRotacion(x,y)

x=x[:,1];
y=y[:,1];

numLados=size(x,1);
largoLados=zeros(numLados,1);
theta=zeros(numLados,1);
cr=zeros(numLados,2);
for i=1:numLados
    if i<numLados
        x1=x[i];
        y1=y[i];
        x2=x[i+1];
        y2=y[i+1];
    else
        x1=x[end];
        y1=y[end];
        x2=x[1];
        y2=y[1];
    end
    d=sqrt((x2-x1)^2+(y2-y1)^2);
    largoLados[i,1]=d;
    theta1=atan((y1-y2)/(x1-x2));
    theta2=abs(theta1)-pi/2;
    if abs(theta1)<=abs(theta2)
        theta[i]=theta1;
    else
        theta[i]=theta2;
    end
    cr[i,:]=[x1 y1];
end
largoLados=largoLados[:,1];
isort = sortperm(largoLados, rev=true);
theta=theta[isort[1:numLados]];
cr=cr[isort[1:numLados],:];

theta, cr

end
